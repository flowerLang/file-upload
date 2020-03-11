<template>
  <el-tabs id="app" type="border-card">
    <el-tab-pane label="多文件上传" style="width: 100%; height: 100%">
      <multiple-files></multiple-files>
    </el-tab-pane>
    <el-tab-pane label="单文件上传">
      <single-file></single-file>
    </el-tab-pane>
  </el-tabs>
</template>

<script>
import multipleFiles from './multiple-files'
import singleFile from './single-file'

export default {
  name: 'app',
  components: { multipleFiles, singleFile }
}
</script>

<style>
  * {
    padding: 0;
    margin: 0;
  }

  html, body {
    height: 100%;
    width: 100%;
    overflow: hidden;
  }

  #app {
    font-family: 'Avenir', Helvetica, Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    color: #2c3e50;
    margin: 20px 20px;
    width: calc(100% - 40px);
    height: calc(100% - 40px);
  }

  .block {
    padding-bottom: 20px;
  }

  .file-box {
    height: 150px;
    width: 250px;
    border-radius: 4px;
    border: 1px dashed #DCDFE6;
    position: relative;
    transition: all .4s;
    text-align: center;
  }

  .file-box:hover {
    border-color: #409EFF;
  }

  .file-box input {
    position: absolute;
    top: 0;
    left: 0;
    opacity: 0;
    cursor: pointer;
    width: 100%;
    height: 100%;
  }

  .file-box .text {
    margin-top: 40px;
    width: 100%;
    text-align: center;
  }

  .file-box i {
    font-size: 50px;
    color: #C0C4CC
  }

  .file-box p {
    color: #909399;
    font-size: 12px;
  }

  em {
    color: #409EFF;
    font-style: normal;
  }

  .cube-container {
    width: 100%;
    margin: 0 auto;
    overflow: hidden;
  }

  .cube-container .cube {
    width: 30px;
    height: 30px;
    border: 1px solid black;
    float: left;
    position: relative;
    margin-right: -1px;
    margin-bottom: -1px;
  }

  .insider {
    position: absolute;
    bottom: 0;
    left: 0;
    width: 100%;
    transition: all .3s;
  }

  .cube-container .cube > .success {
    background: #67C23A;
  }

  .cube-container .cube > .uploading {
    background: #409EFF;
  }

  .cube-container .cube > .error {
    background: #F56C6C;
  }

  .drag {
    border: 2px solid #409EFF;
    background: rgba(70, 158, 255, .1);
  }
  .el-tabs__content {
    box-sizing: border-box;
    width: 100%;
    height: calc(100% - 39px);
    overflow: auto !important;
  }
</style>
