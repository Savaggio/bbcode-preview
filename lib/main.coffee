url = require 'url'
fs = require 'fs-plus'

BBCodePreviewView = null
renderer = null

isBBCodePreviewView = (object) ->
  BBCodePreviewView ?= require './bbcode-preview-view'
  object instanceof BBCodePreviewView

module.exports =
  activate: ->
    if parseFloat(atom.getVersion()) < 1.7
      atom.deserializers.add
        name: 'BBCodePreviewView'
        deserialize: module.exports.createBBCodePreviewView.bind(module.exports)

    atom.commands.add 'atom-workspace',
      'bbcode-preview:toggle': =>
        @toggle()
      'bbcode-preview:copy-html': =>
        @copyHtml()
      'bbcode-preview:toggle-break-on-single-newline': ->
        keyPath = 'bbcode-preview.breakOnSingleNewline'
        atom.config.set(keyPath, not atom.config.get(keyPath))

    previewFile = @previewFile.bind(this)
    atom.commands.add '.tree-view .file .name[data-name$=\\.bbcode]', 'bbcode-preview:preview-file', previewFile
    atom.commands.add '.tree-view .file .name[data-name$=\\.txt]', 'bbcode-preview:preview-file', previewFile

    atom.workspace.addOpener (uriToOpen) =>
      try
        {protocol, host, pathname} = url.parse(uriToOpen)
      catch error
        return

      return unless protocol is 'bbcode-preview:'

      try
        pathname = decodeURI(pathname) if pathname
      catch error
        return

      if host is 'editor'
        @createBBCodePreviewView(editorId: pathname.substring(1))
      else
        @createBBCodePreviewView(filePath: pathname)

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
