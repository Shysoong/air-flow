{ defer, map, delay } = require('lodash')

{ stringify } = require('../../core/modules/prelude')
{ act, react, lift, link, signal, signals } = require("../../core/modules/dataflow")

failure = require('../../core/components/failure')
FlowError = require('../../core/modules/flow-error')
util = require('../../core/modules/util')
format = require('../../core/modules/format')

module.exports = (_, _go, jobs) ->
  _jobViews = signals []
  _hasJobViews = lift _jobViews, (jobViews) -> jobViews.length > 0
  _isLive = signal no
  _isBusy = signal no
  _exception = signal null

  createJobView = (job) ->
    view = ->
      _.insertAndExecuteCell 'cs', "getJob #{stringify job.key.name}" 

    type = switch job.dest.type
      when 'Key<Frame>'
        '数据帧'
      when 'Key<Model>'
        '模型'
      when 'Key<Grid>'
        '网格搜索'
      when 'Key<PartialDependence>'
        '部分依赖'
      when 'Key<AutoML>'
        '自动化建模'
      when 'Key<ScalaCodeResult>'
        'Scala代码执行'
      when 'Key<KeyedVoid>'
        'Void'
      else
        '未知'

    destination: job.dest.name
    type: type
    description: job.description
    startTime: format.Time new Date job.start_time
    endTime: format.Time new Date job.start_time + job.msec
    elapsedTime: util.formatMilliseconds job.msec
    status: job.status
    view: view

  toggleRefresh = ->
    _isLive not _isLive()

  refresh = ->
    _isBusy yes
    _.requestJobs (error, jobs) ->
      _isBusy no
      if error
        _exception failure _, new FlowError '抓取任务出错', error
        _isLive no
      else
        _jobViews map jobs, createJobView
        delay refresh, 2000 if _isLive()

  act _isLive, (isLive) ->
    refresh() if isLive

  initialize = ->
    _jobViews map jobs, createJobView
    defer _go

  initialize()

  jobViews: _jobViews
  hasJobViews: _hasJobViews
  isLive: _isLive
  isBusy: _isBusy
  toggleRefresh: toggleRefresh
  refresh: refresh
  exception: _exception
  template: 'flow-jobs-output'

