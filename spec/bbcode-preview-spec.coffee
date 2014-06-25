path = require 'path'
{WorkspaceView} = require 'atom'
fs = require 'fs-plus'
temp = require 'temp'
wrench = require 'wrench'
BBCodePreviewView = require '../lib/bbcode-preview-view'

describe "BBCode preview package", ->
  beforeEach ->
    fixturesPath = path.join(__dirname, 'fixtures')
    tempPath = temp.mkdirSync('atom')
    wrench.copyDirSyncRecursive(fixturesPath, tempPath, forceDelete: true)
    atom.project.setPath(tempPath)
    jasmine.unspy(window, 'setTimeout')

    atom.workspaceView = new WorkspaceView
    atom.workspace = atom.workspaceView.model
    spyOn(BBCodePreviewView.prototype, 'renderBBCode').andCallThrough()

    waitsForPromise ->
      atom.packages.activatePackage("bbcode-preview")

    waitsForPromise ->
      atom.packages.activatePackage('language-gfm')

  describe "when a preview has not been created for the file", ->
    beforeEach ->
      atom.workspaceView.attachToDom()

    it "splits the current pane to the right with a bbcode preview for the file", ->
      waitsForPromise ->
        atom.workspace.open("subdir/file.txt")

      runs ->
        atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

      waitsFor ->
        BBCodePreviewView::renderBBCode.callCount > 0

      runs ->
        expect(atom.workspaceView.getPaneViews()).toHaveLength 2
        [editorPane, previewPane] = atom.workspaceView.getPaneViews()

        expect(editorPane.items).toHaveLength 1
        preview = previewPane.getActiveItem()
        expect(preview).toBeInstanceOf(BBCodePreviewView)
        expect(preview.getPath()).toBe atom.workspace.getActivePaneItem().getPath()
        expect(editorPane).toHaveFocus()

    describe "when the editor's path does not exist", ->
      it "splits the current pane to the right with a bbcode preview for the file", ->
        waitsForPromise ->
          atom.workspace.open("new.txt")

        runs ->
          atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

        waitsFor ->
          BBCodePreviewView::renderBBCode.callCount > 0

        runs ->
          expect(atom.workspaceView.getPaneViews()).toHaveLength 2
          [editorPane, previewPane] = atom.workspaceView.getPaneViews()

          expect(editorPane.items).toHaveLength 1
          preview = previewPane.getActiveItem()
          expect(preview).toBeInstanceOf(BBCodePreviewView)
          expect(preview.getPath()).toBe atom.workspace.getActivePaneItem().getPath()
          expect(editorPane).toHaveFocus()

    describe "when the editor does not have a path", ->
      it "splits the current pane to the right with a bbcode preview for the file", ->
        waitsForPromise ->
          atom.workspace.open("")

        runs ->
          atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

        waitsFor ->
          BBCodePreviewView::renderBBCode.callCount > 0

        runs ->
          expect(atom.workspaceView.getPaneViews()).toHaveLength 2
          [editorPane, previewPane] = atom.workspaceView.getPaneViews()

          expect(editorPane.items).toHaveLength 1
          preview = previewPane.getActiveItem()
          expect(preview).toBeInstanceOf(BBCodePreviewView)
          expect(preview.getPath()).toBe atom.workspace.getActivePaneItem().getPath()
          expect(editorPane).toHaveFocus()

    describe "when the path contains a space", ->
      it "renders the preview", ->
        waitsForPromise ->
          atom.workspace.open("subdir/file with space.txt")

        runs ->
          atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

        waitsFor ->
          BBCodePreviewView::renderBBCode.callCount > 0

        runs ->
          expect(atom.workspaceView.getPaneViews()).toHaveLength 2
          [editorPane, previewPane] = atom.workspaceView.getPaneViews()

          expect(editorPane.items).toHaveLength 1
          preview = previewPane.getActiveItem()
          expect(preview).toBeInstanceOf(BBCodePreviewView)
          expect(preview.getPath()).toBe atom.workspace.getActivePaneItem().getPath()
          expect(editorPane).toHaveFocus()

    describe "when the path contains accented characters", ->
      it "renders the preview", ->
        waitsForPromise ->
          atom.workspace.open("subdir/áccéntéd.txt")

        runs ->
          atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

        waitsFor ->
          BBCodePreviewView::renderBBCode.callCount > 0

        runs ->
          expect(atom.workspaceView.getPaneViews()).toHaveLength 2
          [editorPane, previewPane] = atom.workspaceView.getPaneViews()

          expect(editorPane.items).toHaveLength 1
          preview = previewPane.getActiveItem()
          expect(preview).toBeInstanceOf(BBCodePreviewView)
          expect(preview.getPath()).toBe atom.workspace.getActivePaneItem().getPath()
          expect(editorPane).toHaveFocus()

  describe "when a preview has been created for the file", ->
    [editorPane, previewPane, preview] = []

    beforeEach ->
      atom.workspaceView.attachToDom()

      waitsForPromise ->
        atom.workspace.open("subdir/file.txt")

      runs ->
        atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

      waitsFor ->
        BBCodePreviewView::renderBBCode.callCount > 0

      runs ->
        [editorPane, previewPane] = atom.workspaceView.getPaneViews()
        preview = previewPane.getActiveItem()
        BBCodePreviewView::renderBBCode.reset()

    it "closes the existing preview when toggle is triggered a second time", ->
      atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

      [editorPane, previewPane] = atom.workspaceView.getPaneViews()
      expect(editorPane).toHaveFocus()
      expect(previewPane?.activeItem).toBeUndefined()

    describe "when the editor is modified", ->
      describe "when the preview is in the active pane but is not the active item", ->
        it "re-renders the preview but does not make it active", ->
          bbcodeEditor = atom.workspace.getActiveEditor()
          previewPane.focus()

          waitsForPromise ->
            atom.workspace.open()

          runs ->
            bbcodeEditor.setText("Hey!")

          waitsFor ->
            BBCodePreviewView::renderBBCode.callCount > 0

          runs ->
            expect(previewPane).toHaveFocus()
            expect(previewPane.getActiveItem()).not.toBe preview

      describe "when the preview is not the active item and not in the active pane", ->
        it "re-renders the preview and makes it active", ->
          previewPane.focus()

          waitsForPromise ->
            atom.workspace.open()

          runs ->
            editorPane.focus()
            atom.workspace.getActiveEditor().setText("Hey!")

          waitsFor ->
            BBCodePreviewView::renderBBCode.callCount > 0

          runs ->
            expect(editorPane).toHaveFocus()
            expect(previewPane.getActiveItem()).toBe preview

      describe "when the liveUpdate config is set to false", ->
        it "only re-renders the bbcode when the editor is saved, not when the contents are modified", ->
          atom.config.set 'bbcode-preview.liveUpdate', false

          contentsModifiedHandler = jasmine.createSpy('contents-modified')
          atom.workspace.getActiveEditor().getBuffer().on 'contents-modified', contentsModifiedHandler
          atom.workspace.getActiveEditor().setText('ch ch changes')

          waitsFor ->
            contentsModifiedHandler.callCount > 0

          runs ->
            expect(BBCodePreviewView::renderBBCode.callCount).toBe 0
            atom.workspace.getActiveEditor().save()
            expect(BBCodePreviewView::renderBBCode.callCount).toBe 1

    describe "when a new grammar is loaded", ->
      it "re-renders the preview", ->
        waitsForPromise ->
          atom.packages.activatePackage('language-javascript')

        waitsFor ->
          BBCodePreviewView::renderBBCode.callCount > 0

  describe "when the bbcode preview view is requested by file URI", ->
    it "opens a preview editor and watches the file for changes", ->
      waitsForPromise "atom.workspace.open promise to be resolved", ->
        atom.workspace.open("bbcode-preview://#{atom.project.resolve('subdir/file.txt')}")

      runs ->
        expect(BBCodePreviewView::renderBBCode.callCount).toBeGreaterThan 0
        preview = atom.workspace.getActivePaneItem()
        expect(preview).toBeInstanceOf(BBCodePreviewView)

        BBCodePreviewView::renderBBCode.reset()
        preview.file.emit('contents-changed')

      waitsFor "renderBBCode to be called", ->
        BBCodePreviewView::renderBBCode.callCount > 0

  describe "when the editor's grammar it not enabled for preview", ->
    it "does not open the bbcode preview", ->
      atom.config.set('bbcode-preview.grammars', [])

      atom.workspaceView.attachToDom()

      waitsForPromise ->
        atom.workspace.open("subdir/file.txt")

      runs ->
        spyOn(atom.workspace, 'open').andCallThrough()
        atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'
        expect(atom.workspace.open).not.toHaveBeenCalled()

  describe "when the editor's path changes", ->
    it "updates the preview's title", ->
      titleChangedCallback = jasmine.createSpy('titleChangedCallback')

      waitsForPromise ->
        atom.workspace.open("subdir/file.txt")

      runs ->
        atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

      waitsFor ->
        BBCodePreviewView::renderBBCode.callCount > 0

      runs ->
        [editorPane, previewPane] = atom.workspaceView.getPaneViews()
        preview = previewPane.getActiveItem()
        expect(preview.getTitle()).toBe 'file.txt Preview'

        titleChangedCallback.reset()
        preview.one('title-changed', titleChangedCallback)
        fs.renameSync(atom.workspace.getActiveEditor().getPath(), path.join(path.dirname(atom.workspace.getActiveEditor().getPath()), 'file2.txt'))

      waitsFor ->
        titleChangedCallback.callCount is 1


  describe "when the URI opened does not have a bbcode-preview protocol", ->
    it "does not throw an error trying to decode the URI (regression)", ->
      waitsForPromise ->
        atom.workspace.open('%')

      runs ->
        expect(atom.workspace.getActiveEditor()).toBeTruthy()

  describe "when bbcode-preview:copy-html is triggered", ->
    it "copies the HTML to the clipboard", ->
      waitsForPromise ->
        atom.workspace.open("subdir/simple.txt")

      runs ->
        atom.workspaceView.getActiveView().trigger 'bbcode-preview:copy-html'
        expect(atom.clipboard.read()).toBe """
          <p><i>italic</i></p>

          <p><b>bold</b></p>

          <p>encoding \u2192 issue</p>
        """

        atom.workspace.getActiveEditor().setSelectedBufferRange [[0, 0], [1, 0]]
        atom.workspaceView.getActiveView().trigger 'bbcode-preview:copy-html'
        expect(atom.clipboard.read()).toBe """
          <p><i>italic</i></p>
        """

  describe "sanitization", ->
    it "removes script tags and attributes that commonly contain inline scripts", ->
      waitsForPromise ->
        atom.workspace.open("subdir/evil.txt")

      runs ->
        atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

      waitsFor ->
        BBCodePreviewView::renderBBCode.callCount > 0

      runs ->
        [editorPane, previewPane] = atom.workspaceView.getPaneViews()
        preview = previewPane.getActiveItem()
        expect(preview[0].innerHTML).toBe """
          <p>hello<br>
          &lt;script src="index.js"&gt;&lt;/script&gt;<br>
          &lt;script&gt;alert('rm -fr')&lt;/script&gt;<br>
          &lt;img onload="alert('rm -rf')" onerror="alert('rm -fr')"&gt;<br>
          world</p>
        """

  describe "when the bbcode contains an <html> tag", ->
    it "does not throw an exception", ->
      waitsForPromise ->
        atom.workspace.open("subdir/html-tag.txt")

      runs ->
        atom.workspaceView.getActiveView().trigger 'bbcode-preview:toggle'

      waitsFor ->
        BBCodePreviewView::renderBBCode.callCount > 0

      runs ->
        [editorPane, previewPane] = atom.workspaceView.getPaneViews()
        preview = previewPane.getActiveItem()
        expect(preview[0].innerHTML).toBe "<p>&lt;html&gt;content&lt;/html&gt;</p>"
