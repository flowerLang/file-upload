<template>
  <el-card shadow="never">
    <h1 slot="header" style="text-align: center">大文件上传和断点续传</h1>
    <div class="block">
      <input type="file" @change="handleFileChange"/>
      <el-button @click="handleUpload">上传</el-button>
      <el-button @click="resumeUpload" v-if="status === Status.pause">恢复</el-button>
      <el-button @click="pauseUpload" v-else :disabled="status !== Status.uploading || !container.hash">暂停</el-button>
    </div>
    <div class="block">
      <div class="block">
        <h3>计算文件hash</h3>
        <el-progress :percentage="hashPercentage"></el-progress>
      </div>
      <div class="block">
        <h3>总进度</h3>
        <el-progress :percentage="fakeUploadPercentage"></el-progress>
      </div>
    </div>
    <div class="block cube-container">
      <div class="cube" v-for="item in data" :key="item.hash">
        <div class="insider" :class="{uploading: item.percentage > 0 && item.percentage < 100, success: item.percentage === 100, error: item.percentage === -1}" :style="{height: item.percentage + '%'}"></div>
      </div>
    </div>
  </el-card>
</template>

<script>
import SparkMD5 from 'spark-md5'
const SIZE = 0.5 * 1024 * 1024 // 切片大小
// eslint-disable-next-line no-unused-vars
const DEV = 'http://localhost:3000'
// eslint-disable-next-line no-unused-vars
const PRD = 'http://116.63.136.129/uploadApi'
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
  name: 'singleFile',
  data () {
    return {
      Status,
      container: {
        file: null,
        worker: null,
        hash: ''
      },
      hashPercentage: 0,
      status: Status.waiting,
      data: [],
      requestList: [],
      fakeUploadPercentage: 0
    }
  },
  computed: {
    uploadPercentage() {
      if (!this.container.file || !this.data.length) return
      const loaded = this.data
        .map(item => item.chunk.size * item.percentage)
        .reduce((acc, cur) => acc + cur)
      return parseInt((loaded / this.container.file.size).toFixed(2))
    }
  },
  watch: {
    uploadPercentage(now) {
      if (now > this.fakeUploadPercentage) {
        this.fakeUploadPercentage = now
      }
    }
  },
  filters: {
    transformByte(val) {
      return Number((val / 1024).toFixed(0))
    }
  },
  methods: {
    handleFileChange (e) {
      const [file] = e.target.files
      if (!file) {
        return
      }
      // 初始化data数据
      Object.assign(this.$data, this.$options.data())
      this.container.file = file
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
    async uploadChunks (uploadedList = []) {
      if (uploadedList.length > 0) {
        this.data.forEach((item) => { item.percentage = uploadedList.includes(item.hash) ? 100 : 0 })
      }
      const requestList = this.data
        .filter(({ hash }) => !uploadedList.includes(hash))
        .map(({ chunk, hash, index, status }) => {
          const formData = new FormData()
          formData.append('chunk', chunk)
          formData.append('hash', hash)
          formData.append('filename', this.container.file.name)
          formData.append('fileHash', this.container.hash)
          return { formData, index, status }
        })
        // .map(({ formData, index }) => new Promise(resolve => {
        //   this.request({
        //     url: url,
        //     data: formData,
        //     onProgress: this.createProgressHandler(this.data[index]),
        //     requestList: this.requestList
        //   }).then(res => resolve(res))
        // }))
        // 全部并发上传
        // await Promise.all(requestList) // 并发切片

      // 控制并发量上传
      await this.sendRequest(requestList) // 并发切片

      // 之前上传的切片数量 + 本次上传的切片数量 = 所有切片数量
      // 合并切片
      if (uploadedList.length + requestList.length === this.data.length) {
        await this.mergeRequest()
      }
    },
    // 合并切片
    async mergeRequest () {
      const { data } = await this.request({
        url: `${url}/merge`,
        headers: {
          'Content-Type': 'application/json;charset=UTF-8'
        },
        data: JSON.stringify({
          filename: this.container.file.name,
          size: SIZE,
          fileHash: this.container.hash
        }),
        requestList: this.requestList
      })
      const { md5 } = JSON.parse(data)
      if (md5 === this.container.hash) {
        this.$message.success('上传成功！')
      } else {
        this.$message.warning('hash值不一致，请重传')
      }
      this.status = Status.waiting
    },
    createProgressHandler(item) {
      return e => {
        item.percentage = parseInt(String((e.loaded / e.total) * 100))
      }
    },
    // 生成文件hash（web-worker）
    calculateHash(fileChunkList) {
      return new Promise(resolve => {
        // 添加worker属性
        this.container.worker = new Worker('/hash.js')
        this.container.worker.postMessage({ fileChunkList })
        this.container.worker.onmessage = e => {
          const { percentage, hash } = e.data
          this.hashPercentage = parseInt(percentage)
          if (hash) {
            resolve(hash)
          }
        }
      })
    },
    // 时间切片计算hash
    async calculateHashIdle(chunks) {
      return new Promise(resolve => {
        const spark = new SparkMD5.ArrayBuffer()
        let count = 0
        let percentage = 0
        // 根据文件内容追加计算
        // eslint-disable-next-line promise/param-names
        const appendToTask = async file => new Promise(resolve1 => {
          const reader = new FileReader()
          reader.readAsArrayBuffer(file)
          reader.onload = e => {
            spark.append(e.target.result)
            resolve1()
          }
        })
        const workLoop = async deadline => {
          // 有任务并且当前帧还没结束
          while (count < chunks.length && deadline.timeRemaining() > 1) {
            await appendToTask(chunks[count++].file)

            if (count < chunks.length) {
              // 计算中
              percentage += Number((100 / chunks.length).toFixed(2))
              this.hashPercentage = parseInt(percentage)
            } else {
              // 计算完成
              this.hashPercentage = 100
              resolve(spark.end())
            }
          }
          window.requestIdleCallback(workLoop)
        }
        window.requestIdleCallback(workLoop)
      })
    },
    // 抽样生成hash
    async calculateHashSample() {
      return new Promise(resolve => {
        const spark = new SparkMD5.ArrayBuffer()
        const reader = new FileReader()
        const file = this.container.file

        // 文件大小
        const size = this.container.file.size
        const offset = SIZE

        this.hashPercentage = 0

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
          this.hashPercentage = parseInt((90 * cur / size).toFixed(2))
          cur += offset
        }
        chunks.push(file.slice(cur))
        const newFile = new Blob(chunks)

        // 拼接
        reader.readAsArrayBuffer(newFile)
        reader.onload = e => {
          spark.append(e.target.result)
          this.hashPercentage = 100
          resolve(spark.end())
        }
      })
    },
    // 控制并发请求量
    async sendRequest(requests, max = 4) {
      const forms = requests.slice()
      return new Promise((resolve, reject) => {
        const len = forms.length
        // let idx = 0
        let counter = 0
        const resendArr = []

        const start = async () => {
          while (counter < len && max > 0) {
            max-- // 占用通道
            // 无重传机制
            // const { formData, index } = forms[idx++]

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
              onProgress: this.createProgressHandler(this.data[index]),
              requestList: this.requestList
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
              this.data[index].percentage = -1 // 报错的进度条
              max++ // 释放当前通道
              start()
            })
          }
        }
        start()
      })
    },
    async verifyUpload(filename, fileHash) {
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
      if (!this.container.file) return
      this.status = Status.uploading

      const fileChunkList = this.createFileChunk(this.container.file)
      // 多线程计算hash
      // this.container.hash = await this.calculateHash(fileChunkList) // web-worker
      // 抽样计算hash
      this.container.hash = await this.calculateHashSample()
      // 时间切片计算hash
      // this.container.hash = await this.calculateHashIdle(fileChunkList) // requestIdleCallback

      const { shouldUpload, uploadedList } = await this.verifyUpload(this.container.file.name, this.container.hash)
      if (!shouldUpload) {
        this.fakeUploadPercentage = 100
        this.$message.success('秒传：上传成功！')
        return
      }

      this.data = fileChunkList.map(({ file }, index) => {
        return {
          fileHash: this.container.hash,
          chunk: file,
          index,
          hash: this.container.hash + '-' + index, // 文件名 + 数组下标
          percentage: uploadedList.includes(index) ? 100 : 0,
          size: file.size,
          status: Status.waiting
        }
      })
      await this.uploadChunks(uploadedList)
    },
    // 暂停上传
    pauseUpload() {
      this.status = Status.pause
      this.requestList.forEach(item => item.abort())
      this.requestList = []
      if (this.container.worker) {
        this.container.worker.onmessage = null
      }
    },
    // 恢复上传
    async resumeUpload() {
      this.status = Status.uploading
      const { uploadedList } = await this.verifyUpload(this.container.file.name, this.container.hash)
      if (!uploadedList) { this.$message.success('上传成功') } else { await this.uploadChunks(uploadedList) }
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
  .cube-container {

  }
</style>
