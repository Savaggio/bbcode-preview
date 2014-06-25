url = require 'url'
fs = require 'fs-plus'

BBCodePreviewView = null # Defer until used
renderer = null # Defer until used

createBBCodePreviewView = (state) ->
  BBCodePreviewView ?= require './bbcode-preview-view'
  new BBCodePreviewView(state)

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
    editor = atom.workspace.getActiveEditor()
    return unless editor?

    grammars = atom.config.get('bbcode-preview.grammars') ? []
    return unless editor.getGrammar().scopeName in grammars

    uri = "bbcode-preview://editor/#{editor.id}"

    previewPane = atom.workspace.paneForUri(uri)
    if previewPane
      previewPane.destroyItem(previewPane.itemForUri(uri))
      return

    previousActivePane = atom.workspace.getActivePane()
    atom.workspace.open(uri, split: 'right', searchAllPanes: true).done (bbcodePreviewView) ->
      if bbcodePreviewView instanceof BBCodePreviewView
        bbcodePreviewView.renderBBCode()
        previousActivePane.activate()

  copyHtml: ->
    editor = atom.workspace.getActiveEditor()
    return unless editor?

    renderer ?= require './bbcode'
    text = editor.getSelectedText() or editor.getText()
    atom.clipboard.write(renderer.bbcode(text))
