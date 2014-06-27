bbcode = require '../lib/bbcode'

describe "BBCode parser", ->

  describe "when parsing text", ->
    it "properly escapes HTML characters", ->
      runs ->
        text = bbcode.bbcode('<script type="text/javascript">alert("Whoops");</script>')
        expect(text).toBe """
          <p>&lt;script type="text/javascript"&gt;alert("Whoops");&lt;/script&gt;</p>
        """

  describe "when handling [url] tags", ->
    it "ignores tags without URLs in them", ->
      runs ->
        text = bbcode.bbcode("[url]not a url[/url]")
        expect(text).toBe "[url]not a url[/url]"

  describe "when handling [img] tags", ->
    it "ignores tags without URLs in them", ->
      runs ->
        text = bbcode.bbcode("[img]not a url[/img]")
        expect(text).toBe "[img]not a url[/img]"

  describe "when handling [code] tags", ->
    it "includes start and end tags", ->
      runs ->
        text = bbcode.bbcode("""
          [code]
          This is some code.
          [/code]
        """)
        expect(text).toBe """
          <pre>
          This is some code.
          </pre>
        """

  describe "when converting newlines", ->
    it "doesn't include a double newline at the end", ->
      runs ->
        text = bbcode.bbcode("""
          This is a block of text
          as if it had come from
          the editor

        """)
        expect(text).toBe("""
          <p>This is a block of text<br>
          as if it had come from<br>
          the editor</p>
        """)
