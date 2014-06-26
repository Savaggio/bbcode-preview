path = require 'path'

{$, $$$, ScrollView} = require 'atom'
_ = require 'underscore-plus'
fs = require 'fs-plus'
{File} = require 'pathwatcher'

bbcode = require './bbcode'

# Custom img tag handler
class ResolvingImgTag
  @nests: false
  @basePath: null

  setBasePath: (basePath) ->
    @basePath = if basePath? then path.dirname(basePath) else null

  resolvePath: (htmlPath) ->
    if @basePath?
      if /^\w+:/.test(htmlPath)
        htmlPath
      else
        path.resolve(@basePath, htmlPath)
    else
      htmlPath

  startTag: (name, arg) ->
    ""

  endTag: ->
    ""

  content: (text) ->
    '<img src="' + bbcode.bbcode.escapeHTMLAttr(@resolvePath(text)) + '">'

module.exports =
class BBCodePreviewView extends ScrollView
  @content: ->
    @div class: 'bbcode-preview native-key-bindings', tabindex: -1

  constructor: ({@editorId, filePath}) ->
    super

    # In order to allow some munging of BBCode options (for example,
    # forums-specific code), we create a local copy. Eventually the preview pane
    # will likely contain controls to change the BBCode version.
    @bbcode = new bbcode.BBCodeParser()
    # We immediately need to inject a new modified image tag that deals with
    # creating relative paths
    @imgTag = new ResolvingImgTag()
    @bbcode.tags["img"] = @imgTag

    if @editorId?
      @resolveEditor(@editorId)
    else
      if atom.workspace?
        @subscribeToFilePath(filePath)
      else
        @subscribe atom.packages.once 'activated', =>
          @subscribeToFilePath(filePath)

  serialize: ->
    deserializer: 'BBCodePreviewView'
    filePath: @getPath()
    editorId: @editorId

  destroy: ->
    @unsubscribe()

  subscribeToFilePath: (filePath) ->
    @file = new File(filePath)
    @trigger 'title-changed'
    @handleEvents()
    @renderBBCode()

  resolveEditor: (editorId) ->
    resolve = =>
      @editor = @editorForId(editorId)

      if @editor?
        @trigger 'title-changed' if @editor?
        @handleEvents()
      else
        # The editor this preview was created for has been closed so close
        # this preview since a preview cannot be rendered without an editor
        @parents('.pane').view()?.destroyItem(this)

    if atom.workspace?
      resolve()
    else
      @subscribe atom.packages.once 'activated', =>
        resolve()
        @renderBBCode()

  editorForId: (editorId) ->
    for editor in atom.workspace.getEditors()
      return editor if editor.id?.toString() is editorId.toString()
    null

  handleEvents: ->
    @subscribe atom.syntax, 'grammar-added grammar-updated', _.debounce((=> @renderBBCode()), 250)
    @subscribe this, 'core:move-up', => @scrollUp()
    @subscribe this, 'core:move-down', => @scrollDown()
    @subscribe this, 'core:save-as', =>
      @saveAs()
      false
    @subscribe this, 'core:copy', =>
      return false if @copyToClipboard()

    @subscribeToCommand atom.workspaceView, 'bbcode-preview:zoom-in', =>
      zoomLevel = parseFloat(@css('zoom')) or 1
      @css('zoom', zoomLevel + .1)

    @subscribeToCommand atom.workspaceView, 'bbcode-preview:zoom-out', =>
      zoomLevel = parseFloat(@css('zoom')) or 1
      @css('zoom', zoomLevel - .1)

    @subscribeToCommand atom.workspaceView, 'bbcode-preview:reset-zoom', =>
      @css('zoom', 1)

    changeHandler = =>
      @renderBBCode()
      pane = atom.workspace.paneForUri(@getUri())
      if pane? and pane isnt atom.workspace.getActivePane()
        pane.activateItem(this)

    if @file?
      @subscribe(@file, 'contents-changed', changeHandler)
    else if @editor?
      @subscribe @editor.getBuffer(), 'contents-modified', =>
        changeHandler() if atom.config.get 'bbcode-preview.liveUpdate'
      @subscribe @editor, 'path-changed', => @trigger 'title-changed'
      @subscribe @editor.getBuffer(), 'reloaded saved', =>
        changeHandler() unless atom.config.get 'bbcode-preview.liveUpdate'

    @subscribe atom.config.observe 'bbcode-preview.breakOnSingleNewline', callNow: false, changeHandler

  renderBBCode: ->
    @showLoading()
    if @file?
      @file.read().then (contents) => @renderBBCodeText(contents)
    else if @editor?
      @renderBBCodeText(@editor.getText())

  renderBBCodeText: (text) ->
    # TODO: Some form of error handling?
    @imgTag.setBasePath(@getPath())
    html = @bbcode.transform(text)
    @loading = false
    @html(html)
    @trigger('bbcode-preview:bbcode-changed')

  getTitle: ->
    if @file?
      "#{path.basename(@getPath())} Preview"
    else if @editor?
      "#{@editor.getTitle()} Preview"
    else
      "BBCode Preview"

  getIconName: ->
    "bbcode"

  getUri: ->
    if @file?
      "bbcode-preview://#{@getPath()}"
    else
      "bbcode-preview://editor/#{@editorId}"

  getPath: ->
    if @file?
      @file.getPath()
    else if @editor?
      @editor.getPath()

  showError: (result) ->
    failureMessage = result?.message

    @html $$$ ->
      @h2 'Previewing BBCode Failed'
      @h3 failureMessage if failureMessage?

  showLoading: ->
    @loading = true
    @html $$$ ->
      @div class: 'bbcode-spinner', 'Loading BBCode\u2026'

  copyToClipboard: ->
    return false if @loading

    selection = window.getSelection()
    selectedText = selection.toString()
    selectedNode = selection.baseNode

    # Use default copy event handler if there is selected text inside this view
    return false if selectedText and selectedNode? and $.contains(@[0], selectedNode)

    atom.clipboard.write(@[0].innerHTML)
    true

  saveAs: ->
    return if @loading

    filePath = @getPath()
    if filePath
      filePath += '.html'
    else
      filePath = 'untitled.bbcode.html'
      if projectPath = atom.project.getPath()
        filePath = path.join(projectPath, filePath)

    if htmlFilePath = atom.showSaveDialogSync(filePath)
      # Hack to prevent encoding issues
      # https://github.com/atom/bbcode-preview/issues/96
      html = @[0].innerHTML.split('').join('')

      fs.writeFileSync(htmlFilePath, html)
      atom.workspace.open(htmlFilePath)
