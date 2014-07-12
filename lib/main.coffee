url = require 'url'
fs = require 'fs-plus'
{$} = require 'atom'

BBCodePreviewView = null # Defer until used
renderer = null # Defer until used

createBBCodePreviewView = (state) ->
  BBCodePreviewView ?= require './bbcode-preview-view'
  new BBCodePreviewView(state)

isBBCodePreviewView = (object) ->
  BBCodePreviewView ?= require './bbcode-preview-view'
  object instanceof BBCodePreviewView

deserializer =
  name: 'BBCodePreviewView'
  deserialize: (state) ->
    BBCodePreviewView(state) if state.constructor is Object
atom.deserializers.add(deserializer)

module.exports =
  configDefaults:
    breakOnSingleNewline: false
    liveUpdate: true
    grammars: [
      'text.plain'
      'text.plain.null-grammar'
    ]

  activate: ->
    atom.workspaceView.command 'bbcode-preview:toggle', =>
      @toggle()

    atom.workspaceView.command 'bbcode-preview:copy-html', =>
      @copyHtml()

    atom.workspaceView.on 'bbcode-preview:preview-file', (event) =>
      @previewFile(event)

    atom.workspaceView.command 'bbcode-preview:toggle-break-on-single-newline', ->
      atom.config.toggle('bbcode-preview.breakOnSingleNewline')

    atom.workspace.registerOpener (uriToOpen) ->
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
        createBBCodePreviewView(editorId: pathname.substring(1))
      else
        createBBCodePreviewView(filePath: pathname)

  toggle: ->
    if isBBCodePreviewView(atom.workspace.activePaneItem)
      atom.workspace.destroyActivePaneItem()
      return

    editor = atom.workspace.getActiveEditor()
    return unless editor?

    grammars = atom.config.get('bbcode-preview.grammars') ? []
    return unless editor.getGrammar().scopeName in grammars

    @addPreviewForEditor(editor) unless @removePreviewForEditor(editor)

  uriForEditor: (editor) ->
    "bbcode-preview://editor/#{editor.id}"

  removePreviewForEditor: (editor) ->
    uri = @uriForEditor(editor)
    previewPane = atom.workspace.paneForUri(uri)
    if previewPane?
      previewPane.destroyItem(previewPane.itemForUri(uri))
      true
    else
      false

  addPreviewForEditor: (editor) ->
    uri = @uriForEditor(editor)
    previousActivePane = atom.workspace.getActivePane()
    atom.workspace.open(uri, split: 'right', searchAllPanes: true).done (bbcodePreviewView) ->
      if isBBCodePreviewView(bbcodePreviewView)
        bbcodePreviewView.renderBBCode()
        previousActivePane.activate()

  previewFile: ({target}) ->
    filePath = $(target).view()?.getPath?()
    return unless filePath

    for editor in atom.workspace.getEditors() when editor.getPath() is filePath
      @addPreviewForEditor(editor)
      return

    atom.workspace.open "bbcode-preview://#{encodeURI(filePath)}", searchAllPanes: true

  copyHtml: ->
    editor = atom.workspace.getActiveEditor()
    return unless editor?

    renderer ?= require './bbcode'
    text = editor.getSelectedText() or editor.getText()
    atom.clipboard.write(renderer.bbcode(text))
