path = require 'path'

{Emitter, Disposable, CompositeDisposable, File} = require 'atom'
_ = require 'underscore-plus'
fs = require 'fs-plus'

renderer = require './renderer'

module.exports =
class BBCodePreviewView
  @deserialize: (params) ->
    new BBCodePreviewView(params)

  constructor: ({@editorId, @filePath}) ->
    @element = document.createElement('div')
    @element.classList.add('bbcode-preview', 'native-key-bindings')
    @element.tabIndex = -1
    @emitter = new Emitter
    @loaded = false
    @disposables = new CompositeDisposable
    @registerScrollCommands()
    if @editorId?
      @resolveEditor(@editorId)
    else if atom.workspace?
      @subscribeToFilePath(@filePath)
    else
      @disposables.add atom.packages.onDidActivateInitialPackages =>
        @subscribeToFilePath(@filePath)

  serialize: ->
    deserializer: 'BBCodePreviewView'
    filePath: @getPath() ? @filePath
    editorId: @editorId

  copy: ->
    new BBCodePreviewView({@editorId, filePath: @getPath() ? @filePath})

  destroy: ->
    @disposables.dispose()
    @element.remove()

  registerScrollCommands: ->
    @disposables.add(atom.commands.add(@element, {
      'core:move-up': =>
        @element.scrollTop -= document.body.offsetHeight / 20
        return
      'core:move-down': =>
        @element.scrollTop += document.body.offsetHeight / 20
        return
      'core:page-up': =>
        @element.scrollTop -= @element.offsetHeight
        return
      'core:page-down': =>
        @element.scrollTop += @element.offsetHeight
        return
      'core:move-to-top': =>
        @element.scrollTop = 0
        return
      'core:move-to-bottom': =>
        @element.scrollTop = @element.scrollHeight
        return
    }))
    return

  onDidChangeTitle: (callback) ->
    @emitter.on 'did-change-title', callback

  onDidChangeModified: (callback) ->
    # No op to suppress deprecation warning
    new Disposable

  onDidChangeBBCode: (callback) ->
    @emitter.on 'did-change-bbcode', callback

  subscribeToFilePath: (filePath) ->
    @file = new File(filePath)
    @emitter.emit 'did-change-title'
    @disposables.add @file.onDidRename(=> @emitter.emit 'did-change-title')
    @handleEvents()
    @renderBBCode()

  resolveEditor: (editorId) ->
    resolve = =>
      @editor = @editorForId(editorId)

      if @editor?
        @emitter.emit 'did-change-title'
        @disposables.add @editor.onDidDestroy(=> @subscribeToFilePath(@getPath()))
        @handleEvents()
        @renderBBCode()
      else
        @subscribeToFilePath(@filePath)

    if atom.workspace?
      resolve()
    else
      @disposables.add atom.packages.onDidActivateInitialPackages(resolve)

  editorForId: (editorId) ->
    for editor in atom.workspace.getTextEditors()
      return editor if editor.id?.toString() is editorId.toString()
    null

  handleEvents: ->
    @disposables.add atom.grammars.onDidAddGrammar => _.debounce((=> @renderBBCode()), 250)
    @disposables.add atom.grammars.onDidUpdateGrammar _.debounce((=> @renderBBCode()), 250)

    atom.commands.add @element,
      'core:save-as': (event) =>
        event.stopPropagation()
        @saveAs()
      'core:copy': (event) =>
        event.stopPropagation() if @copyToClipboard()
      'bbcode-preview:zoom-in': =>
        zoomLevel = parseFloat(getComputedStyle(@element).zoom)
        @element.style.zoom = zoomLevel + 0.1
      'bbcode-preview:zoom-out': =>
        zoomLevel = parseFloat(getComputedStyle(@element).zoom)
        @element.style.zoom = zoomLevel - 0.1
      'bbcode-preview:reset-zoom': =>
        @element.style.zoom = 1

    changeHandler = =>
      @renderBBCode()

      pane = atom.workspace.paneForItem(this)
      if pane? and pane isnt atom.workspace.getActivePane()
        pane.activateItem(this)

    if @file?
      @disposables.add @file.onDidChange(changeHandler)
    else if @editor?
      @disposables.add @editor.getBuffer().onDidStopChanging ->
        changeHandler() if atom.config.get 'bbcode-preview.liveUpdate'
      @disposables.add @editor.onDidChangePath => @emitter.emit 'did-change-title'
      @disposables.add @editor.getBuffer().onDidSave ->
        changeHandler() unless atom.config.get 'bbcode-preview.liveUpdate'
      @disposables.add @editor.getBuffer().onDidReload ->
        changeHandler() unless atom.config.get 'bbcode-preview.liveUpdate'

    @disposables.add atom.config.onDidChange 'bbcode-preview.breakOnSingleNewline', changeHandler

    @disposables.add atom.config.observe 'bbcode-preview.useGitHubStyle', (useGitHubStyle) =>
      if useGitHubStyle
        @element.setAttribute('data-use-github-style', '')
      else
        @element.removeAttribute('data-use-github-style')

  renderBBCode: ->
    @showLoading() unless @loaded
    @getBBCodeSource()
    .then (source) => @renderBBCodeText(source) if source?
    .catch (reason) => @showError({message: reason})

  getBBCodeSource: ->
    if @file?.getPath()
      @file.read().then (source) =>
        if source is null
          Promise.reject("#{@file.getBaseName()} could not be found")
        else
          Promise.resolve(source)
      .catch (reason) -> Promise.reject(reason)
    else if @editor?
      Promise.resolve(@editor.getText())
    else
      Promise.reject()

  getHTML: (callback) ->
    @getBBCodeSource().then (source) =>
      return unless source?

      renderer.toHTML source, @getPath(), @getGrammar(), callback

  renderBBCodeText: (text) ->
    scrollTop = @element.scrollTop
    renderer.toDOMFragment text, @getPath(), @getGrammar(), (error, domFragment) =>
      if error
        @showError(error)
      else
        @loading = false
        @loaded = true
        @element.textContent = ''
        @element.appendChild(domFragment)
        @emitter.emit 'did-change-bbcode'
        @element.scrollTop = scrollTop

  getTitle: ->
    if @file? and @getPath()?
      "#{path.basename(@getPath())} Preview"
    else if @editor?
      "#{@editor.getTitle()} Preview"
    else
      "BBCode Preview"

  getIconName: ->
    "bbcode"

  getURI: ->
    if @file?
      "bbcode-preview://#{@getPath()}"
    else
      "bbcode-preview://editor/#{@editorId}"

  getPath: ->
    if @file?
      @file.getPath()
    else if @editor?
      @editor.getPath()

  getGrammar: ->
    @editor?.getGrammar()

  getDocumentStyleSheets: -> # This function exists so we can stub it
    document.styleSheets

  getTextEditorStyles: ->
    textEditorStyles = document.createElement("atom-styles")
    textEditorStyles.initialize(atom.styles)
    textEditorStyles.setAttribute "context", "atom-text-editor"
    document.body.appendChild textEditorStyles

    # Extract style elements content
    Array.prototype.slice.apply(textEditorStyles.childNodes).map (styleElement) ->
      styleElement.innerText

  getBBCodePreviewCSS: ->
    markdownPreviewRules = []
    ruleRegExp = /\.bbcode-preview/
    cssUrlRegExp = /url\(atom:\/\/bbcode-preview\/assets\/(.*)\)/

    for stylesheet in @getDocumentStyleSheets()
      if stylesheet.rules?
        for rule in stylesheet.rules
          # We only need `.bbcode-review` css
          markdownPreviewRules.push(rule.cssText) if rule.selectorText?.match(ruleRegExp)?

    markdownPreviewRules
      .concat(@getTextEditorStyles())
      .join('\n')
      .replace(/atom-text-editor/g, 'pre.editor-colors')
      .replace(/:host/g, '.host') # Remove shadow-dom :host selector causing problem on FF
      .replace cssUrlRegExp, (match, assetsName, offset, string) -> # base64 encode assets
        assetPath = path.join __dirname, '../assets', assetsName
        originalData = fs.readFileSync assetPath, 'binary'
        base64Data = new Buffer(originalData, 'binary').toString('base64')
        "url('data:image/jpeg;base64,#{base64Data}')"

  showError: (result) ->
    @element.textContent = ''
    h2 = document.createElement('h2')
    h2.textContent = 'Previewing BBCode Failed'
    @element.appendChild(h2)
    if failureMessage = result?.message
      h3 = document.createElement('h3')
      h3.textContent = failureMessage
      @element.appendChild(h3)

  showLoading: ->
    @loading = true
    @element.textContent = ''
    div = document.createElement('div')
    div.classList.add('bbcode-spinner')
    div.textContent = 'Loading BBCode\u2026'
    @element.appendChild(div)

  copyToClipboard: ->
    return false if @loading

    selection = window.getSelection()
    selectedText = selection.toString()
    selectedNode = selection.baseNode

    # Use default copy event handler if there is selected text inside this view
    return false if selectedText and selectedNode? and (@element is selectedNode or @element.contains(selectedNode))

    @getHTML (error, html) ->
      if error?
        console.warn('Copying BBCode as HTML failed', error)
      else
        atom.clipboard.write(html)

    true

  saveAs: ->
    return if @loading

    filePath = @getPath()
    title = 'BBCode to HTML'
    if filePath
      title = path.parse(filePath).name
      filePath += '.html'
    else
      filePath = 'untitled.md.html'
      if projectPath = atom.project.getPaths()[0]
        filePath = path.join(projectPath, filePath)

    if htmlFilePath = atom.showSaveDialogSync(filePath)

      @getHTML (error, htmlBody) =>
        if error?
          console.warn('Saving BBCode as HTML failed', error)
        else

          html = """
            <!DOCTYPE html>
            <html>
              <head>
                  <meta charset="utf-8" />
                  <title>#{title}</title>
                  <style>#{@getBBCodePreviewCSS()}</style>
              </head>
              <body class='bbcode-preview' data-use-github-style>#{htmlBody}</body>
            </html>""" + "\n" # Ensure trailing newline

          fs.writeFileSync(htmlFilePath, html)
          atom.workspace.open(htmlFilePath)
