path = require 'path'

{Emitter, Disposable, CompositeDisposable, File} = require 'atom'
{$, $$$, ScrollView} = require 'atom-space-pen-views'
Grim = require 'grim'
_ = require 'underscore-plus'
fs = require 'fs-plus'

renderer = require './renderer'

module.exports =
class BBCodePreviewView extends ScrollView
  @content: ->
    @div class: 'bbcode-preview native-key-bindings', tabindex: -1

  constructor: ({@editorId, @filePath}) ->
    super
    @emitter = new Emitter
    @disposables = new CompositeDisposable
    @loaded = false

  attached: ->
    return if @isAttached
    @isAttached = true

    if @editorId?
      @resolveEditor(@editorId)
    else
      if atom.workspace?
        @subscribeToFilePath(@filePath)
      else
        @disposables.add atom.packages.onDidActivateInitialPackages =>
          @subscribeToFilePath(@filePath)

  serialize: ->
    deserializer: 'BBCodePreviewView'
    filePath: @getPath() ? @filePath
    editorId: @editorId

  destroy: ->
    @disposables.dispose()

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
    @handleEvents()
    @renderBBCode()

  resolveEditor: (editorId) ->
    resolve = =>
      @editor = @editorForId(editorId)

      if @editor?
        @emitter.emit 'did-change-title' if @editor?
        @handleEvents()
        @renderBBCode()
      else
        # The editor this preview was created for has been closed so close
        # this preview since a preview cannot be rendered without an editor
        atom.workspace?.paneForItem(this)?.destroyItem(this)

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
      'core:move-up': =>
        @scrollUp()
      'core:move-down': =>
        @scrollDown()
      'core:save-as': (event) =>
        event.stopPropagation()
        @saveAs()
      'core:copy': (event) =>
        event.stopPropagation() if @copyToClipboard()
      'bbcode-preview:zoom-in': =>
        zoomLevel = parseFloat(@css('zoom')) or 1
        @css('zoom', zoomLevel + .1)
      'bbcode-preview:zoom-out': =>
        zoomLevel = parseFloat(@css('zoom')) or 1
        @css('zoom', zoomLevel - .1)
      'bbcode-preview:reset-zoom': =>
        @css('zoom', 1)

    changeHandler = =>
      @renderBBCode()

      # TODO: Remove paneForURI call when ::paneForItem is released
      pane = atom.workspace.paneForItem?(this) ? atom.workspace.paneForURI(@getURI())
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
    @getBBCodeSource().then (source) => @renderBBCodeText(source) if source?

  getBBCodeSource: ->
    if @file?.getPath()
      @file.read()
    else if @editor?
      Promise.resolve(@editor.getText())
    else
      Promise.resolve(null)

  getHTML: (callback) ->
    @getBBCodeSource().then (source) =>
      return unless source?

      renderer.toHTML source, @getPath(), @getGrammar(), callback

  renderBBCodeText: (text) ->
    renderer.toDOMFragment text, @getPath(), @getGrammar(), (error, domFragment) =>
      if error
        @showError(error)
      else
        @loading = false
        @loaded = true
        @html(domFragment)
        @emitter.emit 'did-change-bbcode'
        @originalTrigger('bbcode-preview:bbcode-changed')

  getTitle: ->
    if @file?
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
    markdowPreviewRules = []
    ruleRegExp = /\.bbcode-preview/
    cssUrlRefExp = /url\(atom:\/\/bbcode-preview\/assets\/(.*)\)/

    for stylesheet in @getDocumentStyleSheets()
      if stylesheet.rules?
        for rule in stylesheet.rules
          # We only need `.bbcode-review` css
          markdowPreviewRules.push(rule.cssText) if rule.selectorText?.match(ruleRegExp)?

    markdowPreviewRules
      .concat(@getTextEditorStyles())
      .join('\n')
      .replace(/atom-text-editor/g, 'pre.editor-colors')
      .replace(/:host/g, '.host') # Remove shadow-dom :host selector causing problem on FF
      .replace cssUrlRefExp, (match, assetsName, offset, string) -> # base64 encode assets
        assetPath = path.join __dirname, '../assets', assetsName
        originalData = fs.readFileSync assetPath, 'binary'
        base64Data = new Buffer(originalData, 'binary').toString('base64')
        "url('data:image/jpeg;base64,#{base64Data}')"

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
    return false if selectedText and selectedNode? and (@[0] is selectedNode or $.contains(@[0], selectedNode))

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

  isEqual: (other) ->
    @[0] is other?[0] # Compare DOM elements

if Grim.includeDeprecatedAPIs
  BBCodePreviewView::on = (eventName) ->
    # So this isn't really needed but who cares
    if eventName is 'bbcode-preview:bbcode-changed'
      Grim.deprecate("Use BBCodePreviewView::onDidChangeBBCode instead of the 'bbcode-preview:bbcode-changed' jQuery event")
    super
