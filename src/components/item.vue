<template>
  <ul class="list">
    <li class="item" :title="item.file.name">
      {{ item.file.name }}
    </li>
    <li class="item">
      {{ item.file.size | transformByte }}
    </li>
    <li class="item">
      <el-progress :percentage="getPercentage() || item.fakeUploadPercentage"></el-progress>
    </li>
    <li class="item">
      <el-button @click="resumeUpload" v-if="item.status === Status.pause" size="small">恢复</el-button>
      <el-button @click="pauseUpload" v-if="item.status === Status.uploading" size="small">
        暂停
      </el-button>
      <el-button v-if="item.status === Status.waiting" size="small" disabled>等待</el-button>
      <el-button v-if="item.status === Status.done" size="small" disabled>完成</el-button>
    </li>
  </ul>
</template>

<script>
export default {
  name: 'item',
  props: {
    item: {
      type: Object,
      default: null
    },
    title: {
      type: Boolean,
      default: false
    }
  },
  filters: {
    transformByte (val) {
      return Number((val / 1024 / 1024).toFixed(2))
    }
  },
  data () {
    return {
      Status: {
        waiting: 'waiting',
        pause: 'pause',
        uploading: 'uploading',
        done: 'done',
        error: 'error'
      }
    }
  },
  methods: {
    resumeUpload () {
      this.$emit('resume', this.item.index)
    },
    pauseUpload () {
      this.$emit('pause', this.item.index)
    },
    getPercentage() {
      if (this.item.data.length === 0) return
      const loaded = this.item.data
        .map(item => item.chunk.size * item.percentage)
        .reduce((acc, cur) => acc + cur)
      const percentage = parseInt((loaded / this.item.file.size).toFixed(2))
      if (percentage > this.item.fakeUploadPercentage) {
        this.$emit('update', percentage, this.item.index)
        return percentage
      } else {
        return this.item.fakeUploadPercentage
      }
    }
  }
}
</script>
