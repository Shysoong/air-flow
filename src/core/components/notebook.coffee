{ map, defer, head, join, find, escape, last } = require('lodash')

Mousetrap = require('mousetrap')
window.Mousetrap = Mousetrap
require('mousetrap/plugins/global-bind/mousetrap-global-bind')

{ react, link, signal, signals } = require("../modules/dataflow")
{ stringify } = require('../modules/prelude')

status = require('./status')
sidebar = require('./sidebar')
status = require('./status')
about = require('./about')
dialogs = require('../modules/dialogs')
Cell = require('./cell')
util = require('../modules/util')
fileOpenDialog = require('../../ext/components/file-open-dialog')
fileUploadDialog = require('../../ext/components/file-upload-dialog')

exports.init = (_, _renderers) ->
  _localName = signal '未命名的流程'
  react _localName, (name) ->
    document.title = 'AIR' + if name and name.trim() then "- #{name}" else ''

  _remoteName = signal null

  _isEditingName = signal no
  editName = -> _isEditingName yes
  saveName = -> _isEditingName no

  _cells = signals []
  _selectedCell = null
  _selectedCellIndex = -1
  _clipboardCell = null
  _lastDeletedCell = null
  _areInputsHidden = signal no
  _areOutputsHidden = signal no
  _isSidebarHidden = signal no
  _isRunningAll = signal no
  _runningCaption = signal '运行中'
  _runningPercent = signal '0%'
  _runningCellInput = signal ''
  _status = status.init _
  _sidebar = sidebar.init _, _cells
  _about = about.init _
  _dialogs = dialogs.init _

  # initialize the interpreter when the notebook is created
  # one interpreter is shared by all scala cells
  _initializeInterpreter = ->
    _.requestScalaIntp (error,response) ->
      if error
        # Handle the error
        _.scalaIntpId -1
        _.scalaIntpAsync false
      else
        _.scalaIntpId response.session_id
        _.scalaIntpAsync response.async

  sanitizeCellInput = (cellInput) ->
    cellInput.replace /\"password\":\"[^\"]*\"/g, "\"password\":\"\""

  serialize = ->
    cells = for cell in _cells()
      type: cell.type()
      input: sanitizeCellInput cell.input()

    version: '1.0.0'
    cells: cells

  deserialize = (localName, remoteName, doc) ->
    _localName localName
    _remoteName remoteName

    cells = for cell in doc.cells
      createCell cell.type, cell.input
    _cells cells

    selectCell head cells

    # Execute all non-code cells (headings, markdown, etc.)
    for c in _cells()
      c.execute() unless c.isCode()

    return

  createCell = (type='cs', input='') ->
    Cell _, _renderers, type, input

  checkConsistency = ->
    selectionCount = 0
    for cell, i in _cells()
      unless cell
        error "index #{i} is empty"
      else
        if cell.isSelected()
          selectionCount++
    error "selected cell count = #{selectionCount}" if selectionCount isnt 1
    return

  selectCell = (target, scrollIntoView=yes, scrollImmediately=no) ->
    return if _selectedCell is target
    _selectedCell.isSelected no if _selectedCell
    _selectedCell = target
    #TODO also set focus so that tabs don't jump to the first cell
    _selectedCell.isSelected yes
    _selectedCellIndex = _cells.indexOf _selectedCell
    checkConsistency()
    if scrollIntoView
      defer ->
        _selectedCell.scrollIntoView scrollImmediately
    _selectedCell

  cloneCell = (cell) ->
    createCell cell.type(), cell.input()

  switchToCommandMode = ->
    _selectedCell.isActive no

  switchToEditMode = ->
    _selectedCell.isActive yes
    no

  convertCellToCode = ->
    _selectedCell.type 'cs'

  convertCellToHeading = (level) -> ->
    _selectedCell.type "h#{level}"
    _selectedCell.execute()

  convertCellToMarkdown = ->
    _selectedCell.type 'md'
    _selectedCell.execute()

  convertCellToRaw = ->
    _selectedCell.type 'raw'
    _selectedCell.execute()

  convertCellToScala = ->
    _selectedCell.type 'sca'

  copyCell = ->
    _clipboardCell = _selectedCell

  cutCell = ->
    copyCell()
    removeCell()

  deleteCell = ->
    _lastDeletedCell = _selectedCell
    removeCell()

  removeCell = ->
    cells = _cells()
    if cells.length > 1
      if _selectedCellIndex is cells.length - 1
        #TODO call dispose() on this cell
        removedCell = head _cells.splice _selectedCellIndex, 1
        selectCell cells[_selectedCellIndex - 1]
      else
        #TODO call dispose() on this cell
        removedCell = head _cells.splice _selectedCellIndex, 1
        selectCell cells[_selectedCellIndex]
      _.saveClip 'trash', removedCell.type(), removedCell.input() if removedCell
    return

  insertCell = (index, cell) ->
    _cells.splice index, 0, cell
    selectCell cell
    cell

  insertAbove = (cell) ->
    insertCell _selectedCellIndex, cell

  insertBelow = (cell) ->
    insertCell _selectedCellIndex + 1, cell

  appendCell = (cell) ->
    insertCell _cells().length, cell

  insertCellAbove = (type, input) ->
    insertAbove createCell type, input

  insertCellBelow = (type, input) ->
    insertBelow createCell type, input

  insertNewCellAbove = ->
    insertAbove createCell 'cs'

  insertNewCellBelow = ->
    insertBelow createCell 'cs'

  insertNewScalaCellAbove = ->
    insertAbove createCell 'sca'

  insertNewScalaCellBelow = ->
    insertBelow createCell 'sca'

  insertCellAboveAndRun = (type, input) ->
    cell = insertAbove createCell type, input
    cell.execute()
    cell

  insertCellBelowAndRun = (type, input) ->
    cell = insertBelow createCell type, input
    cell.execute()
    cell

  appendCellAndRun = (type, input) ->
    cell = appendCell createCell type, input
    cell.execute()
    cell


  moveCellDown = ->
    cells = _cells()
    unless _selectedCellIndex is cells.length - 1
      _cells.splice _selectedCellIndex, 1
      _selectedCellIndex++
      _cells.splice _selectedCellIndex, 0, _selectedCell
    return

  moveCellUp = ->
    unless _selectedCellIndex is 0
      _cells.splice _selectedCellIndex, 1
      _selectedCellIndex--
      _cells.splice _selectedCellIndex, 0, _selectedCell
    return

  mergeCellBelow = ->
    cells = _cells()
    unless _selectedCellIndex is cells.length - 1
      nextCell = cells[_selectedCellIndex + 1]
      if _selectedCell.type() is nextCell.type()
        nextCell.input _selectedCell.input() + '\n' + nextCell.input()
        removeCell()
    return

  splitCell = ->
    if _selectedCell.isActive()
      input = _selectedCell.input()
      if input.length > 1
        cursorPosition = _selectedCell.getCursorPosition()
        if 0 < cursorPosition < input.length - 1
          left = substr input, 0, cursorPosition
          right = substr input, cursorPosition
          _selectedCell.input left
          insertCell _selectedCellIndex + 1, createCell 'cs', right
          _selectedCell.isActive yes
    return

  pasteCellAbove = ->
    insertCell _selectedCellIndex, cloneCell _clipboardCell if _clipboardCell

  pasteCellBelow = ->
    insertCell _selectedCellIndex + 1, cloneCell _clipboardCell if _clipboardCell

  undoLastDelete = ->
    insertCell _selectedCellIndex + 1, _lastDeletedCell if _lastDeletedCell
    _lastDeletedCell = null

  runCell = ->
    _selectedCell.execute()
    no

  runCellAndInsertBelow = ->
    _selectedCell.execute -> insertNewCellBelow()
    no

  #TODO ipython has inconsistent behavior here. seems to be doing runCellAndInsertBelow if executed on the lowermost cell.
  runCellAndSelectBelow = ->
    _selectedCell.execute -> selectNextCell()
    no

  checkIfNameIsInUse = (name, go) ->
    _.requestObjectExists 'notebook', name, (error, exists) -> go exists

  storeNotebook = (localName, remoteName) ->
    _.requestPutObject 'notebook', localName, serialize(), (error) ->
      if error
        _.alert "保存流程笔记出错：#{error.message}"
      else
        _remoteName localName
        _localName localName
        if remoteName isnt localName # renamed document
          _.requestDeleteObject 'notebook', remoteName, (error) ->
            if error
              _.alert "删除远程笔记[#{remoteName}]出错：#{error.message}"
            _.saved()
        else
          _.saved()

  saveNotebook = ->
    localName = util.sanitizeName _localName()
    return _.alert '无效的笔记名称。' if localName is ''

    remoteName = _remoteName()
    if remoteName # saved document
      storeNotebook localName, remoteName
    else # unsaved document
      checkIfNameIsInUse localName, (isNameInUse) ->
        if isNameInUse
          _.confirm "已经有一个以该名字命名的笔记存在。\n您想要用您正视图保存的笔记来替换它吗？", { acceptCaption: '替换', declineCaption: '取消' }, (accept) ->
            if accept
              storeNotebook localName, remoteName
        else
          storeNotebook localName, remoteName
    return

  promptForNotebook = ->
    _.dialog fileOpenDialog, (result) ->
      if result
        { error, filename } = result
        if error
          _.growl error.message ? error
        else
          loadNotebook filename
          _.loaded()

  uploadFile = ->
    _.dialog fileUploadDialog, (result) ->
      if result
        { error } = result
        if error
          _.growl error.message ? error
        else
          _.growl '文件已经成功上传！'
          _.insertAndExecuteCell 'cs', "setupParse source_frames: [ #{stringify result.result.destination_frame }]"

  toggleInput = ->
    _selectedCell.toggleInput()

  toggleOutput = ->
    _selectedCell.toggleOutput()

  toggleAllInputs = ->
    wereHidden = _areInputsHidden()
    _areInputsHidden not wereHidden
    #
    # If cells are generated while inputs are hidden, the input boxes
    #   do not resize to fit contents. So explicitly ask all cells
    #   to resize themselves.
    #
    if wereHidden
      for cell in _cells()
        cell.autoResize()
    return

  toggleAllOutputs = ->
    _areOutputsHidden not _areOutputsHidden()

  toggleSidebar = ->
    _isSidebarHidden not _isSidebarHidden()

  showBrowser = ->
    _isSidebarHidden no
    _.showBrowser()

  showOutline = ->
    _isSidebarHidden no
    _.showOutline()

  showClipboard = ->
    _isSidebarHidden no
    _.showClipboard()

  selectNextCell = ->
    cells = _cells()
    unless _selectedCellIndex is cells.length - 1
      selectCell cells[_selectedCellIndex + 1]
    return no # prevent arrow keys from scrolling the page

  selectPreviousCell = ->
    unless _selectedCellIndex is 0
      cells = _cells()
      selectCell cells[_selectedCellIndex - 1]
    return no # prevent arrow keys from scrolling the page

  displayKeyboardShortcuts = ->
    $('#keyboardHelpDialog').modal()

  findBuildProperty = (caption) ->
    if _.BuildProperties
      if entry = (find _.BuildProperties, (entry) -> entry.caption is caption)
        entry.value
      else
        undefined
    else
      undefined


  getBuildProperties = ->
    projectVersion = findBuildProperty 'H2O Build project version'
    [
      findBuildProperty 'H2O Build git branch'
      projectVersion
      if projectVersion then last projectVersion.split '.' else undefined
      (findBuildProperty 'H2O Build git hash') or 'master'
    ]

  displayDocumentation = ->
    [ gitBranch, projectVersion, buildVersion, gitHash ] = getBuildProperties()

    if buildVersion and buildVersion isnt '99999'
      window.open "http://h2o-release.s3.amazonaws.com/h2o/#{gitBranch}/#{buildVersion}/docs-website/h2o-docs/index.html", '_blank'
    else
      window.open "https://github.com/h2oai/h2o-3/blob/#{gitHash}/h2o-docs/src/product/flow/README.md", '_blank'

  displayFAQ = ->
    [ gitBranch, projectVersion, buildVersion, gitHash ] = getBuildProperties()

    if buildVersion and buildVersion isnt '99999'
      window.open "http://h2o-release.s3.amazonaws.com/h2o/#{gitBranch}/#{buildVersion}/docs-website/h2o-docs/index.html", '_blank'
    else
      window.open "https://github.com/h2oai/h2o-3/blob/#{gitHash}/h2o-docs/src/product/howto/FAQ.md", '_blank'

  executeCommand = (command) -> ->
    _.insertAndExecuteCell 'cs', command

  displayAbout = ->
    $('#aboutDialog').modal()

  shutdown = ->
    _.requestShutdown (error, result) ->
      if error
        _.growl "关闭失败：#{error.message}", 'danger'
      else
        _.growl '关闭完成！', 'warning'


  showHelp = ->
    _isSidebarHidden no
    _.showHelp()

  createNotebook = ->
    _.confirm '这个操作会替换你当前激活的流程笔记。\n您确定要继续吗？', {acceptCaption: '创建新的流程笔记', declineCaption: '取消'}, (accept) ->
      if accept
        currentTime = (new Date()).getTime()
        deserialize '未命名的流程', null,
          cells: [
            type: 'cs'
            input: ''
          ]

  duplicateNotebook = ->
    deserialize "#{_localName()}的备份", null, serialize()

  openNotebook = (name, doc) ->
    deserialize name, null, doc

  loadNotebook = (name) ->
    _.requestObject 'notebook', name, (error, doc) ->
      if error
        _.alert error.message ? error
      else
        deserialize name, name, doc

  exportNotebook = ->
    if remoteName = _remoteName()
      window.open _.ContextPath + "3/NodePersistentStorage.bin/notebook/#{remoteName}", '_blank'
    else
      _.alert "在导出之前请先保存这个流程笔记。"

  goToH2OUrl = (url) -> ->
    window.open _.ContextPath + url, '_blank'

  goToUrl = (url) -> ->
    window.open url, '_blank'

  executeAllCells = (fromBeginning, go) ->
    _isRunningAll yes

    cells = _cells().slice 0
    cellCount = cells.length
    cellIndex = 0

    unless fromBeginning
      cells = cells.slice _selectedCellIndex
      cellIndex = _selectedCellIndex

    executeNextCell = ->
      if _isRunningAll() # will be false if user-aborted
        cell = cells.shift()
        if cell
          # Scroll immediately without affecting selection state.
          cell.scrollIntoView yes

          cellIndex++
          _runningCaption "Running cell #{cellIndex} of #{cellCount}"
          _runningPercent "#{Math.floor 100 * cellIndex/cellCount}%"
          _runningCellInput cell.input()

          #TODO Continuation should be EFC, and passing an error should abort 'run all'
          cell.execute (errors) ->
            if errors
              go 'failed', errors
            else
              executeNextCell()
        else
          go 'done'
      else
        go 'aborted'

    executeNextCell()

  runAllCells = (fromBeginning=yes) ->
    executeAllCells fromBeginning, (status) ->
      _isRunningAll no
      switch status
        when 'aborted'
          _.growl '您的流程已停止运行', 'warning'
        when 'failed'
          _.growl '您的流程运行失败。', 'danger'
        else # 'done'
          _.growl '您的流程运行结束！', 'success'

  continueRunningAllCells = -> runAllCells no

  stopRunningAll = ->
    _isRunningAll no

  clearCell = ->
    _selectedCell.clear()
    _selectedCell.autoResize()

  clearAllCells = ->
    for cell in _cells()
      cell.clear()
      cell.autoResize()
    return

  notImplemented = -> # noop
  pasteCellandReplace = notImplemented
  mergeCellAbove = notImplemented
  startTour = notImplemented

  #
  # Top menu bar
  #

  createMenu = (label, items) ->
    label: label
    items: items

  createMenuHeader = (label) ->
    label: label
    action: null

  createShortcutHint = (shortcut) ->
    "<span style='float:right'>" + (map shortcut, (key) -> "<kbd>#{ key }</kbd>").join(' ') + "</span>"

  createMenuItem = (label, action, shortcut) ->
    kbds = if shortcut
      createShortcutHint shortcut
    else
      ''

    label: "#{ escape label }#{ kbds }"
    action: action

  menuDivider = label: null, action: null

  _menus = signal null

  menuCell = [
        createMenuItem '运行单元格', runCell, ['ctrl', 'enter']
        menuDivider
        createMenuItem '剪切单元格', cutCell, ['x']
        createMenuItem '复制单元格', copyCell, ['c']
        createMenuItem '粘贴到单元格之上', pasteCellAbove, ['shift', 'v']
        createMenuItem '粘贴到单元格之下', pasteCellBelow, ['v']
        #TODO createMenuItem 'Paste Cell and Replace', pasteCellandReplace, yes
        createMenuItem '删除单元格', deleteCell, ['d', 'd']
        createMenuItem '撤消删除单元格', undoLastDelete, ['z']
        menuDivider
        createMenuItem '上移单元格', moveCellUp, ['ctrl', 'k']
        createMenuItem '下移单元格', moveCellDown, ['ctrl', 'j']
        menuDivider
        createMenuItem '上插单元格', insertNewCellAbove, ['a']
        createMenuItem '下插单元格', insertNewCellBelow, ['b']
        #TODO createMenuItem 'Split Cell', splitCell
        #TODO createMenuItem 'Merge Cell Above', mergeCellAbove, yes
        #TODO createMenuItem 'Merge Cell Below', mergeCellBelow
        menuDivider
        createMenuItem '切换单元格可见性', toggleInput
        createMenuItem '切换单元格输出可见性', toggleOutput, ['o']
        createMenuItem '清除单元格输出', clearCell
        ]

  menuCellSW = [
        menuDivider
        createMenuItem '上插Scala单元格', insertNewScalaCellAbove
        createMenuItem '下插Scala单元格', insertNewScalaCellBelow
        ]
  if _.onSparklingWater
    menuCell = [menuCell..., menuCellSW...]

  initializeMenus = (builder) ->
    modelMenuItems = [createMenuItem('运行自动机器学习...', executeCommand 'runAutoML'), menuDivider]
    modelMenuItems = modelMenuItems.concat map(builder, (builder) ->
      createMenuItem("#{ builder.algo_full_name }...", executeCommand "buildModel #{stringify builder.algo}")
    )
    modelMenuItems = modelMenuItems.concat [
      menuDivider
      createMenuItem '列出所有模型', executeCommand 'getModels'
      createMenuItem '列出网格搜索结果', executeCommand 'getGrids'
      createMenuItem '导入模型...', executeCommand 'importModel'
      createMenuItem '导出模型...', executeCommand 'exportModel'
    ]

    [
      createMenu '流程笔记', [
        createMenuItem '新建笔记', createNotebook
        createMenuItem '打开笔记...', promptForNotebook
        createMenuItem '保存笔记', saveNotebook, ['s']
        createMenuItem '生成拷贝...', duplicateNotebook
        menuDivider
        createMenuItem '运行所有单元格', runAllCells
        createMenuItem '运行后续所有单元格', continueRunningAllCells
        menuDivider
        createMenuItem '切换所有单元格可见性', toggleAllInputs
        createMenuItem '切换所有单元格输出可见性', toggleAllOutputs
        createMenuItem '清除所有单元格输出', clearAllCells
        menuDivider
        createMenuItem '下载本流程笔记...', exportNotebook
      ]
    ,
      createMenu '单元格', menuCell
    ,
      createMenu '数据', [
        createMenuItem '导入文件...', executeCommand 'importFiles'
        createMenuItem '导入数据库表...', executeCommand 'importSqlTable'
        createMenuItem '上传文件...', uploadFile
        createMenuItem '拆分数据帧...', executeCommand 'splitFrame'
        createMenuItem '合并数据帧...', executeCommand 'mergeFrames'
        menuDivider
        createMenuItem '列出所有数据帧', executeCommand 'getFrames'
        menuDivider
        createMenuItem '插补...', executeCommand 'imputeColumn'
        #TODO Quantiles
        #TODO Interaction
      ]
    ,
      createMenu '模型', modelMenuItems
    ,
      createMenu '评价', [
        createMenuItem '预测...', executeCommand 'predict'
        createMenuItem '部分依赖图...', executeCommand 'buildPartialDependence'
        menuDivider
        createMenuItem '列出所有的预测信息', executeCommand 'getPredictions'
        #TODO Confusion Matrix
        #TODO AUC
        #TODO Hit Ratio
        #TODO PCA Score
        #TODO Gains/Lift Table
        #TODO Multi-model Scoring
      ]
    ,
      createMenu '管理', [
        createMenuItem '任务作业', executeCommand 'getJobs'
        createMenuItem '集群状态', executeCommand 'getCloud'
        createMenuItem '气量计(CPU状态)', goToH2OUrl 'perfbar.html'
        menuDivider
        createMenuHeader '日志检查'
        createMenuItem '查看日志', executeCommand 'getLogFile'
        createMenuItem '下载日志', goToH2OUrl '3/Logs/download'
        menuDivider
        createMenuHeader '高级'
        createMenuItem '下载h2o-genmodel.jar', goToH2OUrl '3/h2o-genmodel.jar'
        createMenuItem '创建合成数据帧...', executeCommand 'createFrame'
        createMenuItem '堆栈信息', executeCommand 'getStackTrace'
        createMenuItem '网络测试', executeCommand 'testNetwork'
        #TODO Cluster I/O
        createMenuItem '分析器', executeCommand 'getProfile depth: 10'
        createMenuItem '时间轴', executeCommand 'getTimeline'
        #TODO UDP Drop Test
        #TODO Task Status
        createMenuItem '关闭服务器', shutdown
      ]
    ,
      createMenu '帮助', [
        #TODO createMenuItem 'Tour', startTour, yes
        createMenuItem '建模助手', executeCommand 'assist'
        menuDivider
        createMenuItem '展示帮助内容', showHelp
        createMenuItem '快捷键', displayKeyboardShortcuts, ['h']
        menuDivider
        createMenuItem '文档', displayDocumentation
        createMenuItem '常见问题', displayFAQ
        createMenuItem '官网', goToUrl 'http://www.skyease.io/'
        createMenuItem 'Air Github 地址', goToUrl 'https://github.com/Shysoong/air-flow'
        createMenuItem '报告问题', goToUrl 'http://jira.h2o.ai'
        createMenuItem '论坛 / 提问', goToUrl 'https://groups.google.com/d/forum/h2ostream'
        menuDivider
        #TODO Tutorial Flows
        createMenuItem '关于', displayAbout
      ]
    ]

  setupMenus = ->
    _.requestModelBuilders (error, builders) ->
      _menus initializeMenus if error then [] else builders

  createTool = (icon, label, action, isDisabled=no) ->
    label: label
    action: action
    isDisabled: isDisabled
    icon: "fa fa-#{icon}"

  _toolbar = [
    [
      createTool 'file-o', '新建', createNotebook
      createTool 'folder-open-o', '打开', promptForNotebook
      createTool 'save', '保存(s)', saveNotebook
    ]
  ,
    [
      createTool 'plus', '下插单元格(b)', insertNewCellBelow
      createTool 'arrow-up', '上移单元格(ctrl+k)', moveCellUp
      createTool 'arrow-down', '下移单元格(ctrl+j)', moveCellDown
    ]
  ,
    [
      createTool 'cut', '剪切单元格(x)', cutCell
      createTool 'copy', '复制单元格(c)', copyCell
      createTool 'paste', '粘贴到单元格之下(v)', pasteCellBelow
      createTool 'eraser', '清除单元格输出', clearCell
      createTool 'trash-o', '删除单元格(d d)', deleteCell
    ]
  ,
    [
      createTool 'step-forward', '运行并选取下方单元格', runCellAndSelectBelow
      createTool 'play', '运行(ctrl+enter)', runCell
      createTool 'forward', '运行所有', runAllCells
    ]
  ,
    [
      createTool 'question-circle', '建模助手', executeCommand 'assist'
    ]
  ]

  # (From IPython Notebook keyboard shortcuts dialog)
  # The IPython Notebook has two different keyboard input modes. Edit mode allows you to type code/text into a cell and is indicated by a green cell border. Command mode binds the keyboard to notebook level actions and is indicated by a grey cell border.
  #
  # Command Mode (press Esc to enable)
  #
  normalModeKeyboardShortcuts = [
    [ 'enter', '切换到编辑模式', switchToEditMode ]
    #[ 'shift+enter', 'run cell, select below', runCellAndSelectBelow ]
    #[ 'ctrl+enter', 'run cell', runCell ]
    #[ 'alt+enter', 'run cell, insert below', runCellAndInsertBelow ]
    [ 'y', '转到代码格式', convertCellToCode ]
    [ 'm', '转到markdown格式', convertCellToMarkdown ]
    [ 'r', '转到原始格式', convertCellToRaw ]
    [ '1', '转到一级标题格式', convertCellToHeading 1 ]
    [ '2', '转到二级标题格式', convertCellToHeading 2 ]
    [ '3', '转到三级标题格式', convertCellToHeading 3 ]
    [ '4', '转到四级标题格式', convertCellToHeading 4 ]
    [ '5', '转到五级标题格式', convertCellToHeading 5 ]
    [ '6', '转到六级标题格式', convertCellToHeading 6 ]
    [ 'up', '选择上一个单元格', selectPreviousCell ]
    [ 'down', '选择下一个单元格', selectNextCell ]
    [ 'k', '选择上一个单元格', selectPreviousCell ]
    [ 'j', '选择下一个单元格', selectNextCell ]
    [ 'ctrl+k', '上移单元格', moveCellUp ]
    [ 'ctrl+j', '下移单元格', moveCellDown ]
    [ 'a', '上插单元格', insertNewCellAbove ]
    [ 'b', '下插单元格', insertNewCellBelow ]
    [ 'x', '剪切单元格', cutCell ]
    [ 'c', '复制单元格', copyCell ]
    [ 'shift+v', '粘贴到单元格之上', pasteCellAbove ]
    [ 'v', '粘贴到单元格之下', pasteCellBelow ]
    [ 'z', '撤消删除', undoLastDelete ]
    [ 'd d', '删除单元格', deleteCell ]
    [ 'shift+m', '合并下方单元格', mergeCellBelow ]
    [ 's', '保存笔记', saveNotebook ]
    #[ 'mod+s', 'save notebook', saveNotebook ]
    # [ 'l', 'toggle line numbers' ]
    [ 'o', '切换单元格输出可见性', toggleOutput ]
    # [ 'shift+o', 'toggle output scrolling' ]
    [ 'h', '键盘快捷键', displayKeyboardShortcuts ]
    # [ 'i', 'interrupt kernel (press twice)' ]
    # [ '0', 'restart kernel (press twice)' ]
  ]

  if _.onSparklingWater
    normalModeKeyboardShortcuts.push [ 'q', 'to Scala', convertCellToScala ]



  #
  # Edit Mode (press Enter to enable)
  #
  editModeKeyboardShortcuts = [
    # Tab : code completion or indent
    # Shift-Tab : tooltip
    # Cmd-] : indent
    # Cmd-[ : dedent
    # Cmd-a : select all
    # Cmd-z : undo
    # Cmd-Shift-z : redo
    # Cmd-y : redo
    # Cmd-Up : go to cell start
    # Cmd-Down : go to cell end
    # Opt-Left : go one word left
    # Opt-Right : go one word right
    # Opt-Backspace : del word before
    # Opt-Delete : del word after
    [ 'esc', '切换到命令模式', switchToCommandMode ]
    [ 'ctrl+m', '切换到命令模式', switchToCommandMode ]
    [ 'shift+enter', '运行并选取下方单元格', runCellAndSelectBelow ]
    [ 'ctrl+enter', '运行单元格', runCell ]
    [ 'alt+enter', '运行并下插单元格', runCellAndInsertBelow ]
    [ 'ctrl+shift+-', '拆分单元格', splitCell ]
    [ 'mod+s', '保存笔记', saveNotebook ]
  ]

  toKeyboardHelp = (shortcut) ->
    [ seq, caption ] = shortcut
    keystrokes = (map seq.split(/\+/g), (key) -> "<kbd>#{key}</kbd>").join ' '
    keystrokes: keystrokes
    caption: caption

  normalModeKeyboardShortcutsHelp = map normalModeKeyboardShortcuts, toKeyboardHelp
  editModeKeyboardShortcutsHelp = map editModeKeyboardShortcuts, toKeyboardHelp

  setupKeyboardHandling = (mode) ->
    for [ shortcut, caption, f ] in normalModeKeyboardShortcuts
      Mousetrap.bind shortcut, f

    for [ shortcut, caption, f ] in editModeKeyboardShortcuts
      Mousetrap.bindGlobal shortcut, f

    return

  initialize = ->
    setupKeyboardHandling 'normal'

    setupMenus()

    link _.load, loadNotebook
    link _.open, openNotebook

    link _.selectCell, selectCell

    link _.executeAllCells, executeAllCells

    link _.insertAndExecuteCell, (type, input) ->
      defer appendCellAndRun, type, input

    link _.insertCell, (type, input) ->
      defer insertCellBelow, type, input

    link _.saved, ->
      _.growl 'Notebook saved.'

    link _.loaded, ->
      _.growl 'Notebook loaded.'

    do (executeCommand 'assist')

    _.setDirty() #TODO setPristine() when autosave is implemented.
    if _.onSparklingWater
      _initializeInterpreter()

  link _.ready, initialize

  name: _localName
  isEditingName: _isEditingName
  editName: editName
  saveName: saveName
  menus: _menus
  sidebar: _sidebar
  status: _status
  toolbar: _toolbar
  cells: _cells
  areInputsHidden: _areInputsHidden
  areOutputsHidden: _areOutputsHidden
  isSidebarHidden: _isSidebarHidden
  isRunningAll: _isRunningAll
  runningCaption: _runningCaption
  runningPercent: _runningPercent
  runningCellInput: _runningCellInput
  stopRunningAll: stopRunningAll
  toggleSidebar: toggleSidebar
  shortcutsHelp:
    normalMode: normalModeKeyboardShortcutsHelp
    editMode: editModeKeyboardShortcutsHelp
  about: _about
  dialogs: _dialogs
  templateOf: (view) -> view.template
