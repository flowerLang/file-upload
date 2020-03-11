<template>
  <div class="infinite-list-container" ref="list" @scroll="scrollEvent">
    <div class="infinite-list-phantom" ref="phantom" :style="{height: listHeight + 'px'}"></div>
    <div class="infinite-list" ref="content" :style="{transform: getTransform}">
      <div class="infinite-list-item" :id="item.index" :key="item.index" v-for="item in visibleData" ref="items">
        <slot :item="item" />
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'virtualList',
  props: {
    listData: {
      type: Array,
      default: () => []
    },
    // 预估高度
    estimatedItemSize: {
      type: Number,
      required: true
    },
    // 缓冲区比例
    bufferScale: {
      type: Number,
      default: 1
    }
  },
  watch: {
    listData() {
      this.initPositions()
    }
  },
  computed: {
    // 列表总高度
    listHeight () {
      if (this.positions.length > 0) {
        return this.positions[this.positions.length - 1].bottom
      } else {
        return 0
      }
    },
    // 可显示的列表项数
    visibleCount() {
      return Math.ceil(this.screenHeight / this.estimatedItemSize)
    },
    // 偏移量对应的style
    getTransform() {
      return `translate3d(0, ${this.startOffset}px, 0)`
    },
    // 可视区上方渲染条数
    aboveCount() {
      return Math.min(this.start, Math.floor(this.bufferScale * this.visibleCount))
    },
    // 可视区下方渲染条数
    belowCount() {
      return Math.min(this.listData.length - this.end, Math.floor(this.bufferScale * this.visibleCount))
    },
    // 获取真实显示列表数据
    visibleData () {
      let start = this.start - this.aboveCount
      let end = this.end + this.belowCount
      return this.listData.slice(start, end)
    }
  },
  data () {
    return {
      // 起始索引
      start: 0,
      // 结束索引
      end: 0,
      // 可视区高度
      screenHeight: 0,
      // 偏移量
      startOffset: 0,
      // 每个列表项对应的位置
      positions: []
    }
  },
  mounted () {
    this.$nextTick(() => {
      this.screenHeight = this.$el.clientHeight
      this.start = 0
      this.end = this.start + this.visibleCount
    })
  },
  methods: {
    scrollEvent() {
      // 当前滚动位置
      let scrollTop = this.$refs.list.scrollTop
      // 此时的开始索引
      this.start = this.getStartIndex(scrollTop)
      // 此时的结束索引
      this.end = this.start + this.visibleCount
      // 此时的偏移量
      this.setStartOffset()
    },
    // 初始化每个列表项的位置信息
    initPositions() {
      this.positions = this.listData.map((item, index) => {
        return {
          index,
          height: this.estimatedItemSize,
          top: index * this.estimatedItemSize,
          bottom: (index + 1) * this.estimatedItemSize
        }
      })
    },
    // 更新渲染后列表项的位置信息
    updatePositions() {
      let nodes = this.$refs.items
      nodes.forEach((node) => {
        let rect = node.getBoundingClientRect()
        let height = rect.height
        let index = node.id
        let oldHeight = this.options[index].height
        let dValue = height - oldHeight
        if (dValue) {
          this.positions[index].bottom += dValue
          this.positions[index].height = height
          for (let i = index + 1; i < this.positions.length; i++) {
            this.positions[i].top = this.positions[i - 1].bottom
            this.positions[i].bottom += dValue
          }
        }
      })
    },
    // 获取列表起始索引项
    getStartIndex(scrollTop = 0) {
      // 获取 列表项第一个 bottom > scrollTop 的索引
      return this.binarySearch(this.positions, scrollTop)
    },
    // 获取当前的偏移量
    setStartOffset() {
      if (this.start >= 1) {
        let size = this.positions[this.start].top - (this.positions[this.start - this.aboveCount] ? this.positions[this.start - this.aboveCount].top : 0)
        this.startOffset = this.positions[this.start - 1].bottom - size
      } else {
        this.startOffset = 0
      }
    },
    // 二分查找
    binarySearch(list, value) {
      let start = 0
      let end = list.length - 1
      let tempIndex = null
      while (start <= end) {
        let midIndex = Math.floor((start + end) / 2)
        let midValue = list[midIndex].bottom
        if (midValue === value) {
          return midIndex + 1
        } else if (midValue < value) {
          start = midIndex + 1
        } else {
          if (tempIndex === null || tempIndex > midIndex) {
            tempIndex = midIndex
          }
          end = end - 1
        }
      }

      return tempIndex
    }
  }
}
</script>

<style scoped>
  .infinite-list-container {
    width: 100%;
    height: 100%;
    overflow: auto;
    position: relative;
  }

  .infinite-list-phantom {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    z-index: -1;
  }

  .infinite-list {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
  }
</style>
