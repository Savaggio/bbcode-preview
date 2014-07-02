path = require 'path'
{WorkspaceView} = require 'atom'
fs = require 'fs-plus'
temp = require 'temp'
BBCodePreviewView = require '../lib/bbcode-preview-view'

describe "BBCodePreviewView", ->
  [file, preview] = []

  beforeEach ->
    atom.workspaceView = new WorkspaceView
    atom.workspace = atom.workspaceView.model

    filePath = atom.project.resolve('subdir/file.txt')
    preview = new BBCodePreviewView({filePath})

    waitsForPromise ->
      atom.packages.activatePackage('language-ruby')

  afterEach ->
    preview.destroy()

  describe "::constructor", ->
    it "shows a loading spinner and renders the bbcode", ->
      preview.showLoading()
      expect(preview.find('.bbcode-spinner')).toExist()

      waitsForPromise ->
        preview.renderBBCode()

      # FIXME: This is looking for something we don't inject at present
      #runs ->
      #  expect(preview.find(".emoji")).toExist()

    it "shows an error message when there is an error", ->
      preview.showError("Not a real file")
      expect(preview.text()).toContain "Failed"

  describe "serialization", ->
    newPreview = null

    afterEach ->
      newPreview.destroy()

    it "recreates the file when serialized/deserialized", ->
      newPreview = atom.deserializers.deserialize(preview.serialize())
      expect(newPreview.getPath()).toBe preview.getPath()

    it "serializes the editor id when opened for an editor", ->
      preview.destroy()

      waitsForPromise ->
        atom.workspace.open('new.txt')

      runs ->
        preview = new BBCodePreviewView({editorId: atom.workspace.getActiveEditor().id})
        expect(preview.getPath()).toBe atom.workspace.getActiveEditor().getPath()

        newPreview = atom.deserializers.deserialize(preview.serialize())
        expect(newPreview.getPath()).toBe preview.getPath()

  # These might be implemented at some point in the future
  # describe "code block tokenization", ->
  #   beforeEach ->
  #     waitsForPromise ->
  #       preview.renderBBCode()
  #
  #   describe "when the code block's fence name has a matching grammar", ->
  #     it "tokenizes the code block with the grammar", ->
  #       expect(preview.find("pre span.entity.name.function.ruby")).toExist()
  #
  #   describe "when the code block's fence name doesn't have a matching grammar", ->
  #     it "does not tokenize the code block", ->
  #       expect(preview.find("pre code:not([class])").children().length).toBe 0
  #       expect(preview.find("pre code.lang-kombucha").children().length).toBe 0
  #
  #   describe "when the code block contains empty lines", ->
  #     it "doesn't remove the empty lines", ->
  #       expect(preview.find("pre code.lang-python").children().length).toBe 6
  #       expect(preview.find("pre code.lang-python div:nth-child(2)").html()).toBe '&nbsp;'
  #       expect(preview.find("pre code.lang-python div:nth-child(4)").html()).toBe '&nbsp;'
  #       expect(preview.find("pre code.lang-python div:nth-child(5)").html()).toBe '&nbsp;'
  #
  #   describe "when the code block is nested", ->
  #     it "detects and styles the block", ->
  #       expect(preview.find("pre:has(code.lang-javascript)")).toHaveClass 'editor-colors'

  describe "image resolving", ->
    beforeEach ->
      waitsForPromise ->
        preview.renderBBCode()

    describe "when the image uses a relative path", ->
      it "ignores the [img] tag", ->
        preview.find("p")
        #image = preview.find("img").eq(0)
        expect(image.attr('src')).toBe atom.project.resolve('subdir/image1.png')

    describe "when the image uses an absolute path", ->
      it "ignores the [img] tag", ->
        image = preview.find("img").eq(1)
        expect(image.attr('src')).toBe path.normalize(path.resolve('/tmp/image2.png'))

    describe "when the image uses a web URL", ->
      it "doesn't change the URL", ->
        image = preview.find("img").eq(2)
        expect(image.attr('src')).toBe 'http://github.com/image3.png'

  describe "when core:save-as is triggered", ->
    beforeEach ->
      preview.destroy()
      filePath = atom.project.resolve('subdir/simple.txt')
      preview = new BBCodePreviewView({filePath})

    it "saves the rendered HTML and opens it", ->
      outputPath = temp.path(suffix: '.html')
      expect(fs.isFileSync(outputPath)).toBe false

      waitsForPromise ->
        preview.renderBBCode()

      runs ->
        spyOn(atom, 'showSaveDialogSync').andReturn(outputPath)
        preview.trigger 'core:save-as'
        outputPath = fs.realpathSync(outputPath)
        expect(fs.isFileSync(outputPath)).toBe true

      waitsFor ->
        atom.workspace.getActiveEditor()?.getPath() is outputPath

      runs ->
        expect(atom.workspace.getActiveEditor().getText()).toBe """
          <p><i>italic</i></p>

          <p><b>bold</b></p>

          <p>encoding \u2192 issue</p>
        """

  describe "when core:copy is triggered", ->
    beforeEach ->
      preview.destroy()
      filePath = atom.project.resolve('subdir/simple.txt')
      preview = new BBCodePreviewView({filePath})

    it "writes the rendered HTML to the clipboard", ->
      waitsForPromise ->
        preview.renderBBCode()

      runs ->
        preview.trigger 'core:copy'
        expect(atom.clipboard.read()).toBe """
          <p><i>italic</i></p>

          <p><b>bold</b></p>

          <p>encoding \u2192 issue</p>
        """
