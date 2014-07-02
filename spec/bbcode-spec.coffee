bbcode = require '../lib/bbcode'

describe "BBCode parser", ->

  describe "when parsing text", ->
    it "properly escapes HTML characters", ->
      runs ->
        text = bbcode.bbcode('<script type="text/javascript">alert("Whoops");</script>')
        expect(text).toBe """
          <p>&lt;script type="text/javascript"&gt;alert("Whoops");&lt;/script&gt;</p>
        """

  describe "when parsing tags", ->
    it "ignores case", ->
      runs ->
        text = bbcode.bbcode "[b]Test[/b]"
        expect(text).toBe "<b>Test</b>"
        text = bbcode.bbcode "[b]Test[/B]"
        expect(text).toBe "<b>Test</b>"
        text = bbcode.bbcode "[B]Test[/b]"
        expect(text).toBe "<b>Test</b>"
        text = bbcode.bbcode "[B]Test[/B]"
        expect(text).toBe "<b>Test</b>"

  describe "when handling [url] tags", ->
    it "ignores tags without URLs in them", ->
      runs ->
        text = bbcode.bbcode("[url]not a url[/url]")
        expect(text).toBe "[url]not a url[/url]"
    it "allows HTTP URLs", ->
      runs ->
        text = bbcode.bbcode("[url=http://www.example.com]test[/url]")
        expect(text).toBe "<a href=\"http://www.example.com\" rel=\"nofollow\">test</a>"
    it "allows HTTP URLs regardless of case", ->
      runs ->
        text = bbcode.bbcode("[url=HTTP://WWW.EXAMPLE.COM]test[/url]")
        expect(text).toBe "<a href=\"HTTP://WWW.EXAMPLE.COM\" rel=\"nofollow\">test</a>"
    it "allows HTTPS URLs", ->
      runs ->
        text = bbcode.bbcode("[url=https://www.example.com]test[/url]")
        expect(text).toBe "<a href=\"https://www.example.com\" rel=\"nofollow\">test</a>"
    it "allows HTTPS URLs regardless of case", ->
      runs ->
        text = bbcode.bbcode("[url=HTTPS://WWW.EXAMPLE.COM]test[/url]")
        expect(text).toBe "<a href=\"HTTPS://WWW.EXAMPLE.COM\" rel=\"nofollow\">test</a>"

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
