url = require 'url'
fs = require 'fs-plus'

BBCodePreviewView = null
renderer = null

isBBCodePreviewView = (object) ->
  BBCodePreviewView ?= require './bbcode-preview-view'
  object instanceof BBCodePreviewView

module.exports =
  activate: ->
    atom.commands.add 'atom-workspace',
      'bbcode-preview:toggle': =>
        @toggle()
      'bbcode-preview:copy-html': =>
        @copyHtml()
      'bbcode-preview:save-as-html': =>
        @saveAsHtml()
      'bbcode-preview:toggle-break-on-single-newline': ->
        keyPath = 'bbcode-preview.breakOnSingleNewline'
        atom.config.set(keyPath, not atom.config.get(keyPath))

    previewFile = @previewFile.bind(this)
    atom.commands.add '.tree-view .file .name[data-name$=\\.bbcode]', 'bbcode-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.txt]', 'bbcode-preview:preview-file', previewFile

    atom.workspace.addOpener (uriToOpen) =>
      [protocol, path] = uriToOpen.split('://')
      return unless protocol is 'bbcode-preview'

      try
        path = decodeURI(path)
      catch
        return

      if path.startsWith 'editor/'
        @createBBCodePreviewView(editorId: path.substring(7))
      else
        @createBBCodePreviewView(filePath: path)

  createBBCodePreviewView: (state) ->
    if state.editorId or fs.isFileSync(state.filePath)
      BBCodePreviewView ?= require './bbcode-preview-view'
      new BBCodePreviewView(state)

  toggle: ->
    if isBBCodePreviewView(atom.workspace.getActivePaneItem())
      atom.workspace.destroyActivePaneItem()
      return

    editor = atom.workspace.getActiveTextEditor()
    return unless editor?

    grammars = atom.config.get('bbcode-preview.grammars') ? []
    return unless editor.getGrammar().scopeName in grammars

    @addPreviewForEditor(editor) unless @removePreviewForEditor(editor)

  uriForEditor: (editor) ->
    "bbcode-preview://editor/#{editor.id}"

  removePreviewForEditor: (editor) ->
    uri = @uriForEditor(editor)
    previewPane = atom.workspace.paneForURI(uri)
    if previewPane?
      previewPane.destroyItem(previewPane.itemForURI(uri))
      true
    else
      false

  addPreviewForEditor: (editor) ->
    uri = @uriForEditor(editor)
    previousActivePane = atom.workspace.getActivePane()
    options =
      searchAllPanes: true
    if atom.config.get('bbcode-preview.openPreviewInSplitPane')
      options.split = 'right'
    atom.workspace.open(uri, options).then (bbcodePreviewView) ->
      if isBBCodePreviewView(bbcodePreviewView)
        previousActivePane.activate()

  previewFile: ({target}) ->
    filePath = target.dataset.path
    return unless filePath

    for editor in atom.workspace.getTextEditors() when editor.getPath() is filePath
      @addPreviewForEditor(editor)
      return

    atom.workspace.open "bbcode-preview://#{encodeURI(filePath)}", searchAllPanes: true

  copyHtml: ->
    editor = atom.workspace.getActiveTextEditor()
    return unless editor?

    renderer ?= require './renderer'
    text = editor.getSelectedText() or editor.getText()
    renderer.toHTML text, editor.getPath(), editor.getGrammar(), (error, html) ->
      if error
        console.warn('Copying BBCode as HTML failed', error)
      else
        atom.clipboard.write(html)

  saveAsHtml: ->
    activePane = atom.workspace.getActivePaneItem()
    if isBBCodePreviewView(activePane)
      activePane.saveAs()
      return

    editor = atom.workspace.getActiveTextEditor()
    return unless editor?

    grammars = atom.config.get('bbcode-preview.grammars') ? []
    return unless editor.getGrammar().scopeName in grammars

    uri = @uriForEditor(editor)
    bbcodePreviewPane = atom.workspace.paneForURI(uri)
    return unless bbcodePreviewPane?

    previousActivePane = atom.workspace.getActivePane()
    bbcodePreviewPane.activate()
    activePane = atom.workspace.getActivePaneItem()

    if isBBCodePreviewView(activePane)
      activePane.saveAs().then ->
        previousActivePane.activate()
