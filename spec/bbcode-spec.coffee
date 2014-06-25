bbcode = require '../lib/bbcode'

describe "BBCode parser", ->

  describe "when parsing text", ->
    it "properly escapes HTML characters", ->
      runs ->
        text = bbcode.bbcode('<script type="text/javascript">alert("Whoops");</script>')
        expect(text).toBe """
          <p>&lt;script type="text/javascript"&gt;alert("Whoops");&lt;/script&gt;</p>
        """
    it "properly escapes HTML characters in [img] tags", ->
      runs ->
        text = bbcode.bbcode("""
          [img]" onload="alert('rm -rf')[/img]
        """)
        expect(text).toBe """
          <p><img src="&quot; onload=&quot;alert(&#39;rm -rf&#39;)"></p>
        """
    it "properly escapes HTML characters in [url] tags", ->
      runs ->
        text = bbcode.bbcode("""
          [url=" onclick="alert('rm -rf')]Click me![/url]
        """)
        expect(text).toBe """
          <p><a href="&quot; onclick=&quot;alert(&#39;rm -rf&#39;)" rel="nofollow">Click me!</a></p>
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
