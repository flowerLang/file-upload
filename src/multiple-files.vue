<template>
  <el-card shadow="never" ref="card" style="width: 100%; height: 100%">
    <h3 slot="header" style="text-align: center">多文件上传和断点续传</h3>
    <div class="file-box" :class="{ drag }">
      <div class="text">
        <i class="el-icon-upload"/>
        <p>将文件拖到此处，或<em>点击</em>上传</p>
      </div>
      <input type="file" title=""
             @dragenter.prevent="handleDrag(true)"
             @dragleave.prevent="handleDrag(false)"
             @drop="handleFileChange" multiple @change="handleFileChange"/>
    </div>
    <el-button @click="handleUpload">上传</el-button>
    <el-button @click="resumeUpload" v-if="status === Status.pause">恢复</el-button>
    <el-button @click="pauseUpload" v-else :disabled="status !== Status.uploading">暂停</el-button>
    <div class="wrapper" ref="wrapper">
      <div class="block" style="background: #fff">
        <h3>总进度</h3>
        <el-progress :percentage="fakeUploadPercentage"></el-progress>
      </div>
      <ul class="title list">
        <li class="item">文件名</li>
        <li class="item">文件大小（MB）</li>
        <li class="item">上传进度</li>
        <li class="item">操作</li>
      </ul>
      <div class="table" ref="tableWrapper">
        <virtual-list :list-data="fileContainer" v-slot="slotProps" :estimated-item-size="50" :buffer-scale="0.5">
          <item :item="slotProps.item" :index="slotProps.index"
                :title="slotProps.index === 0"
                @resume="resumeUpload"
                @pause="pauseUpload"
                @update="changePercentage"
          ></item>
        </virtual-list>
        <!--<el-table class="block" style="margin-bottom: 0" ref="table" :data="fileContainer">
          &lt;!&ndash;<el-table-column type="expand">
            <template slot-scope="props">
              <div class="cube-container">
                <div class="cube" v-for="item in props.row.data" :key="item.hash">
                  <div class="insider"
                       :class="{uploading: item.percentage > 0 && item.percentage < 100, success: item.percentage === 100, error: item.percentage === -1}"
                       :style="{height: item.percentage + '%'}"></div>
                </div>
              </div>
            </template>
          </el-table-column>&ndash;&gt;
          <el-table-column
            label="文件名"
            width="350"
          >
            <template v-slot="{ row }">
              <p :title="row.file.name"
                 style="text-overflow: ellipsis; white-space: nowrap; overflow: hidden; width: 100%; height: 23px;">{{
                row.file.name }}</p>
            </template>
          </el-table-column>
          <el-table-column
            label="大小(MB)"
            align="center"
            width="100"
          >
            <template v-slot="{ row }">
              <p>{{ row.file.size | transformByte }}</p>
            </template>
          </el-table-column>
          <el-table-column
            label="上传进度"
            align="center"
          >
            <template v-slot="{ row }">
              <el-progress
                :percentage="getPercentage(row) || row.fakeUploadPercentage"
                color="#909399"
              ></el-progress>
            </template>
          </el-table-column>
          <el-table-column label="操作" width="90">
            <template v-slot="{ row, $index }">
              <el-button @click="resumeUpload($index)" v-if="row.status === Status.pause" size="medium">恢复</el-button>
              <el-button @click="pauseUpload($index)" v-if="row.status === Status.uploading" size="medium">
                暂停
              </el-button>
              <el-button v-if="row.status === Status.waiting" disabled>等待</el-button>
              <el-button v-if="row.status === Status.done" disabled>完成</el-button>
            </template>
          </el-table-column>
        </el-table>-->
      </div>
    </div>
  </el-card>
</template>

<script>
import SparkMD5 from 'spark-md5'
import virtualList from './components/virtualList'
import item from './components/item'

const SIZE = 0.5 * 1024 * 1024 // 切片大小
// eslint-disable-next-line no-unused-vars
const DEV = 'http://localhost:3000'
// eslint-disable-next-line no-unused-vars
const PRD = 'http://116.63.136.129/upload'
const env = 'production'

let url = DEV
if (env === 'production') {
  url = PRD
}

const Status = {
  waiting: 'waiting',
  pause: 'pause',
  uploading: 'uploading',
  done: 'done',
  error: 'error'
}

export default {
  name: 'multipleFiles',
  components: { virtualList, item },
  data () {
    return {
      Status,
      status: Status.waiting,
      requestList: [],
      fakeUploadPercentage: 0,
      drag: false,
      fileContainer: [],
      fileSizeSum: 0,
      max: 4,
      index: 0
    }
  },
  computed: {
    uploadPercentage () {
      if (this.fileContainer.length === 0) return 0
      const loaded = this.fileContainer
        .map(item => item.file.size * item.fakeUploadPercentage)
        .reduce((acc, cur) => acc + cur)
      return parseInt((loaded / this.fileSizeSum).toFixed(2))
    }
  },
  watch: {
    uploadPercentage (now) {
      if (now > this.fakeUploadPercentage) {
        this.fakeUploadPercentage = now
      }
    }
  },
  filters: {
    transformByte (val) {
      return Number((val / 1024 / 1024).toFixed(2))
    }
  },
  methods: {
    handleFileChange (e) {
      if (!e.target.files) {
        return
      }
      // 初始化data数据
      Object.assign(this.$data, this.$options.data())
      e.target.files.forEach((item, index) => {
        this.fileContainer.push({
          index,
          file: item,
          worker: null,
          hash: '',
          hashPercentage: 0,
          fakeUploadPercentage: 0,
          status: Status.waiting,
          requestList: [],
          data: []
        })
      })

      if (this.fileContainer.length > 0) {
        this.fileSizeSum = this.fileContainer.map(item => item.file.size).reduce((acc, cur) => acc + cur)
      }
    },
    handleDrag (flag) {
      this.drag = flag
    },
    // 生成文件切片
    createFileChunk (file, size = SIZE) {
      const fileChunkList = []
      let cur = 0
      while (cur < file.size) {
        fileChunkList.push({ file: file.slice(cur, cur + size) })
        cur += size
      }
      return fileChunkList
    },
    // 上传切片
    async uploadChunks (container, uploadedList = []) {
      container.status = Status.uploading
      if (uploadedList && uploadedList.length && uploadedList.length > 0) {
        container.data.forEach((item) => {
          item.percentage = uploadedList.includes(item.hash) ? 100 : 0
        })
      }
      const requestList = container.data
        .filter(({ hash }) => !uploadedList.includes(hash))
        .map(({ chunk, hash, index, status }) => {
          const formData = new FormData()
          formData.append('chunk', chunk)
          formData.append('hash', hash)
          formData.append('filename', container.file.name)
          formData.append('fileHash', container.hash)
          return { formData, index, status }
        })

      if (requestList.length > 0) {
        // 控制并发量上传
        await this.sendRequest(container, requestList) // 并发切片
      }

      // 之前上传的切片数量 + 本次上传的切片数量 = 所有切片数量
      // 合并切片
      if (uploadedList.length + requestList.length === container.data.length) {
        await this.mergeRequest(container)
      }
    },
    // 合并切片
    async mergeRequest (container) {
      const { data } = await this.request({
        url: `${url}/merge`,
        headers: {
          'Content-Type': 'application/json;charset=UTF-8'
        },
        data: JSON.stringify({
          filename: container.file.name,
          size: SIZE,
          fileHash: container.hash
        }),
        requestList: container.requestList
      })
      const { md5 } = JSON.parse(data)
      container.fakeUploadPercentage = 100

      if (md5 === container.hash) {
        if (this.fakeUploadPercentage === 100) { this.$message.success('上传成功！') }
      } else {
        this.$message.warning(`文件 ${container.file.name} hash值不一致，请重传`)
      }
      container.status = Status.done
    },
    createProgressHandler (item) {
      return e => {
        item.percentage = parseInt(String((e.loaded / e.total) * 100))
      }
    },
    // 抽样生成 hash
    async calculateHashSample (container) {
      return new Promise(resolve => {
        const spark = new SparkMD5.ArrayBuffer()
        const reader = new FileReader()
        const file = container.file

        // 文件大小
        const size = container.file.size
        const offset = SIZE

        container.hashPercentage = 0

        const chunks = [file.slice(0, offset)]
        let cur = offset
        while (cur + offset < size) {
          // 取 2M 切片的前中后各 2B
          // 前
          chunks.push(file.slice(cur, cur + 2))
          // 中
          chunks.push(file.slice(cur + offset / 2, cur + offset / 2 + 2))
          // 后
          chunks.push(file.slice(cur + offset - 2, cur + offset))
          container.hashPercentage = parseInt((90 * cur / size).toFixed(2))
          cur += offset
        }
        chunks.push(file.slice(cur))
        const newFile = new Blob(chunks)

        // 拼接
        reader.readAsArrayBuffer(newFile)
        reader.onload = e => {
          spark.append(e.target.result)
          container.hashPercentage = 100
          resolve(spark.end())
        }
      })
    },
    // 控制并发请求量
    async sendRequest (container, requests, max = 3) {
      const forms = requests.slice()
      return new Promise((resolve, reject) => {
        const len = forms.length
        let counter = 0
        const resendArr = []

        const start = async () => {
          while (counter < len && max > 0) {
            max-- // 占用通道
            // 任务不能仅仅累加获取，而是要根据状态
            // wait和error的可以发出请求 方便重试
            const idx = forms.findIndex(v => v.status === Status.waiting || v.status === Status.error)
            if (idx === -1) {
              return
            }
            forms[idx].status = Status.uploading
            const { formData, index } = forms[idx]

            this.request({
              url,
              data: formData,
              onProgress: this.createProgressHandler(container.data[index]),
              requestList: container.requestList
            }).then(() => {
              forms[idx].status = Status.done
              // 释放并发量
              max++
              counter++
              if (counter === len) {
                resolve()
              } else {
                start()
              }
            }).catch((e) => {
              forms[idx].status = Status.error
              forms.splice(idx, 1)
              if (typeof resendArr[index] !== 'number') {
                resendArr[index] = 0
              }
              // 重传次数累加
              resendArr[index]++
              // 一个请求报错3次
              if (resendArr[index] >= 2) {
                return reject(e)
              }
              container.data[index].percentage = -1 // 报错的进度条
              max++ // 释放当前通道
              start()
            })
          }
        }
        if (container.status === Status.uploading) { start() }
      })
    },
    async verifyUpload (filename, fileHash) {
      const { data } = await this.request({
        url: `${url}/verify`,
        headers: {
          'Content-Type': 'application/json'
        },
        data: JSON.stringify({
          filename,
          fileHash
        })
      })
      return JSON.parse(data)
    },
    async handleUpload () {
      if (this.fileContainer.length === 0) return

      this.status = Status.uploading

      // 抽样计算hash
      const len = this.fileContainer.length

      const start = () => {
        while (this.index < len && this.max > 0 && this.status === Status.uploading) {
          this.max--
          const container = this.fileContainer[this.index++]
          container.status = Status.uploading
          this.calculateHashSample(container).then(async (res) => {
            container.hash = res

            // 已上传的切片
            const { shouldUpload, uploadedList } = await this.verifyUpload(container.file.name, res)

            if (!shouldUpload) {
              container.fakeUploadPercentage = 100
              container.status = Status.done
              this.$nextTick(() => {
                if (this.fakeUploadPercentage === 100) {
                  this.$message.success('上传成功')
                }
              })
              if (this.status === Status.uploading) {
                this.max++
                start()
              }
              return
            }

            // 文件切片
            container.data = this.createFileChunk(container.file)
              .map(({ file }, index) => {
                return {
                  fileHash: container.hash,
                  chunk: file,
                  index,
                  hash: container.hash + '-' + index, // 文件名 + 数组下标
                  percentage: 0,
                  size: file.size,
                  status: Status.waiting
                }
              })
            // 上传切片
            this.uploadChunks(container, uploadedList).then(() => {
              if (this.status === Status.uploading) {
                this.max++
                start()
              }
            })
          })
        }
      }
      if (this.status === Status.uploading) { start() }
    },
    // 暂停上传
    pauseUpload (index = -1) {
      if (index > -1) {
        this.max++
        this.fileContainer[index].status = Status.pause
        this.fileContainer[index].requestList.forEach(item => item.abort())
        this.fileContainer[index].requestList = []
        this.handleUpload()
      } else {
        this.status = Status.pause
        for (let i = 0; i < this.fileContainer.length; i++) {
          if (this.fileContainer[i].status !== Status.done) {
            this.fileContainer[i].status = Status.pause
            this.fileContainer[i].requestList.forEach(item => item.abort())
            this.fileContainer[i].requestList = []
          }
        }
      }
    },
    // 恢复上传
    async resumeUpload (index = -1) {
      if (index > -1) {
        this.max--
        this.fileContainer[index].status = Status.uploading
        if (this.fileContainer[index].hash.length === 0) {
          this.fileContainer[index].hash = await this.calculateHashSample(this.fileContainer[index])
        }
        const { shouldUpload, uploadedList } = await this.verifyUpload(this.fileContainer[index].file.name, this.fileContainer[index].hash)
        if (!shouldUpload) {
          this.fileContainer[index].status = Status.done
          if (this.fileContainer.length === 1) { this.$message.success('上传成功') }
        } else {
          this.fileContainer[index].data = this.createFileChunk(this.fileContainer[index].file)
            .map(({ file }, index) => {
              return {
                fileHash: this.fileContainer[index].hash,
                chunk: file,
                index,
                hash: this.fileContainer[index].hash + '-' + index, // 文件名 + 数组下标
                percentage: 0,
                size: file.size,
                status: Status.waiting
              }
            })
          await this.uploadChunks(this.fileContainer[index], uploadedList)
        }
        this.max++
      } else {
        this.status = Status.uploading
        this.fileContainer.forEach((item) => { item.status = item.status !== 'done' ? 'waiting' : 'done' })
        let index = 0; let max = 4
        const start = async () => {
          while (index < this.fileContainer.length && max > 0) {
            max--
            const container = this.fileContainer[index++]
            if (container.status === Status.waiting) {
              container.status = Status.uploading
              if (container.hash.length === 0) {
                container.hash = await this.calculateHashSample(container)
              }
              this.verifyUpload(container.file.name, container.hash)
                .then(({ shouldUpload, uploadedList }) => {
                  if (!shouldUpload) {
                    container.status = Status.done
                    if (this.fileContainer.length === 1) { this.$message.success('上传成功') }
                    max++
                    start()
                  } else {
                    container.data = this.createFileChunk(container.file)
                      .map(({ file }, index) => {
                        return {
                          fileHash: container.hash,
                          chunk: file,
                          index,
                          hash: container.hash + '-' + index, // 文件名 + 数组下标
                          percentage: 0,
                          size: file.size,
                          status: Status.waiting
                        }
                      })
                    this.uploadChunks(container, uploadedList).then(() => {
                      max++
                      start()
                    })
                  }
                })
            } else {
              max++
            }
          }
        }
        start()
      }
    },
    getPercentage(container) {
      if (container.data.length === 0) return
      const loaded = container.data
        .map(item => item.chunk.size * item.percentage)
        .reduce((acc, cur) => acc + cur)
      const percentage = parseInt((loaded / container.file.size).toFixed(2))
      if (percentage > container.fakeUploadPercentage) { container.fakeUploadPercentage = percentage }
      return percentage
    },
    changePercentage(percentage, index) {
      this.fileContainer[index].fakeUploadPercentage = percentage
    },
    request ({ url, method = 'post', data, headers = {}, onProgress = e => e, requestList = [] }) {
      return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest()
        xhr.upload.onprogress = onProgress
        xhr.open(method, url)
        Object.keys(headers).forEach((key) => {
          xhr.setRequestHeader(key, headers[key])
        })
        xhr.send(data)
        xhr.onload = e => {
          if (requestList) {
            const xhrIndex = requestList.findIndex(item => item === xhr)
            requestList.splice(xhrIndex, 1)
          }
          if (xhr.status === 200) {
            resolve({
              data: e.target.response
            })
          } else {
            reject(new Error(`Error!! status: ${xhr.status}`))
          }
        }
        // 暴露当前xhr给外部
        requestList.push(xhr)
      })
    }
  }
}
</script>

<style>
  .el-card__body {
    position: relative;
    width: 100%;
    box-sizing: border-box;
    height: calc(100% - 80px);
  }
  .wrapper {
    position: absolute;
    bottom: 20px;
    left: 0;
    padding: 0 20px;
    right: 0;
    top: 192px;
    background: #fff;
    transition: all 0.4s;
  }
  .table {
    overflow: auto;
    margin-right: -10px;
    padding-right: 10px;
    height: calc(100% - 112px)
  }
  .file-box {
    display: inline-block;
    margin-right: 20px;
    vertical-align: bottom;
    margin-bottom: 0;
  }

  .list {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 50px;
    font-size: 14px;
    list-style: none;
    border-bottom: 1px solid #EBEEF5;
  }

  .title {
    font-weight: bold;
    color: #909399;
  }

  .item:first-child {
    width: 300px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .item:nth-child(2) {
    width: 110px;
    text-align: center;
  }

  .item:nth-child(3) {
    padding-left: 10px;
    flex: 1;
  }

  .item:last-child {
    width: 90px;
    text-align: center;
  }
</style>
