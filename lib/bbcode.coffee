# Module for dealing with BBcode.
# This module is extensible, allowing "new" BBCode to be added.
# Tags may optionally take an argument, and closing tags may optionally require
# the closing argument to match. (So [list=1][/list=1] versus [list=1][/list])

# Very basic tag class that simply generates HTML.
class Tag
  # @param [String] html the HTML tag to generate for the start/end tags.
  # @param [String] cssClass CSS classes to stick in the start tag.
  constructor: (html, cssClass) ->
    if html?
      @html_start = "<" + html
      if cssClass?
        @html_start += ' class="' + cssClass + '"'
      @html_start += ">";
      @html_end = "</" + html + ">";
    else
      @html_start = this.html_end = "";

  # Whether or not this tag "nests" with other tags - if false, everything
  # before its ending tag will be passed to content. Otherwise, subtags will
  # be parsed.
  nests: true
  # Start a tag. May either return a string that is interested as HTML directly
  # or instead an Object that is a Tag that contains whatever state is required
  # to deal with content and endTag.
  startTag: (name, arg) ->
    @html_start

  # Receive the tag content. If "nests" is true, this is ONLY called for
  # text that passes through it before being given to other tags.
  content: (str) ->
    str

  endTag: (name, arg) ->
    @html_end

class URLTag extends Tag
  constructor: ->
    super("a")
  startTag: (name, arg) ->
    '<a href="' + escapeHTMLAttr(arg) + '" rel="nofollow">'

class ImgTag extends Tag
  constructor: ->
    super("img")
  @nests: false
  startTag: (name, arg) ->
    null # Do nothing.
  content: (str) ->
    '<img src="' + escapeHTMLAttr(str) + '">'
  endTag: (name, arg) ->
    null # Also do nothing

class QuoteTag extends Tag
  constructor: ->
    super("blockquote", "quote")
  startTag: (name, arg) ->
    if arg?
      '<div class="quote-by">' + escapeHTML(arg) + ' wrote:</div>' + @start_html
    else
      @start_html

class PreTag extends Tag
  constructor: ->
    super("pre")
  @nests: false

# Conceptually CodeTag has more to it than pre, but for now, it's identical
class CodeTag extends PreTag

escapeHTML = (str) ->
  str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

escapeHTMLAttr = (str) ->
  escapeHTML(str).replace(/"/g, '&quot;').replace(/'/g, '&#39;')

convertNewlinesToHTML = (text) ->
  if (text.length == 0)
    return "<p></p>";
  # First, normalize newlines
  text = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  # Remove the final newline if there is one
  if (text.charAt(text.length-1) == "\n")
    text = text.substring(0,text.length-1)
  # And convert
  text = text.replace(/\n/g, "<br>\n").replace(/<br>\n<br>\n/g, "</p>\n\n<p>")
  '<p>' + text + '</p>'

class TagTokenizer
  constructor: (str) ->
    @str = str
    @currentOffset = 0
    @nextToken = @_next()

  # Determines if the text is a valid tag (allowed between [ and ])
  isValidTag: (tag) ->
    /^\/?[A-Za-z]+(?:=[^\]]*|="[^"]*")?$/.test(tag)

  hasNext: ->
    @nextToken != null

  next: ->
    if (@nextToken == null)
      throw Error("No more tokens")
    result = @nextToken
    if (@nextToken.type == 'text')
      # Merge text tokens if there are any
      nextNext = @_next()
      while nextNext != null and nextNext.type == 'text'
        result.text += nextNext.text
        nextNext = @_next()
      @nextToken = nextNext
    else
      @nextToken = @_next()
    if (result.type == 'tag' and result.name.charAt(0) == '/')
      result.name = result.name.substring(1)
      result.type = 'endtag';
    result

  #
  # Internal implementation of next, before multiple text tokens are merged.
  #
  _next: ->
    #console.log("_next(%d)", this.currentOffset);
    console.log(@str)
    if (@currentOffset >= @str.length)
      return null;
    # This is fairly simple: are we starting with a [?
    if (@str.charAt(@currentOffset) == '[')
      # Assume this is a tag for now
      idx = @str.indexOf(']', @currentOffset)
      if (idx < 0)
        # Last token! Because we can never find an end tag
        tok = { type: 'text', text: @str.substring(@currentOffset) }
        @currentOffset = @str.length
        return tok
      # Otherwise, grab the contents as a tag, maybe
      tag = @str.substring(@currentOffset+1, idx)
      # Is this a real tag?
      if (@isValidTag(tag))
        # OK - now we split it into a tag and an argument (if any)
        name = tag;
        arg = null;
        eqIdx = tag.indexOf('=');
        if (eqIdx >= 0)
          name = tag.substring(0, eqIdx);
          arg = tag.substring(eqIdx + 1);
          # If the argument is surrounded by quotes, remove them
          if (arg.charAt(0) == '"' && arg.charAt(arg.length-1) == '"')
            arg.substring(1, arg.length-1);
        raw = @str.substring(@currentOffset, idx+1);
        @currentOffset = idx+1;
        # Always canonicalize the tokenized name to lower case
        return { type: 'tag', name: name.toLowerCase(), arg: arg, raw: raw }
      else
        # We don't like this tag, so we just return the current text
        # element, advance by one, and continue.
        @currentOffset++;
        return { type: 'text', text: '[' }
    else
      idx = @str.indexOf('[', @currentOffset)
      if idx < 0
        # last text token
        tok = { type: 'text', text: @str.substring(@currentOffset) };
        @currentOffset = @str.length;
        return tok;
      else
        tok = { type: 'text', text: @str.substring(@currentOffset, idx) };
        @currentOffset = idx;
        return tok;

#
# @constructor
#
class BBCodeParser
  constructor: ->
    # Clone the tags as a new object since they may be altered.
    @tags = {};
    for k in BBCodeParser.DEFAULT_TAGS
      @tags[k] = BBCodeParser.DEFAULT_TAGS[k]
  @DEFAULT_TAGS:
    'url': new URLTag(),
    'img': new ImgTag(),
    'quote': new QuoteTag(),
    'pre': new PreTag(),
    'code': new CodeTag(),
    'b': new Tag('b'),
    'i': new Tag('i'),
    'u': new Tag('u'),
    's': new Tag('strike')

  @EM_TAG: new Tag('em');
  @STRONG_TAG: new Tag('strong');

  # Sets whether or not to use &lt;em&gt; and &lt;strong&gt; instead of
  # &lt;i&gt; and &lt;b&gt;. It's debatable which is correct.
  #
  setUseEmStrong: (useEmStrong) ->
    if (useEmStrong)
      @tags['i'] = BBCodeParser.EM_TAG;
      @tags['b'] = BBCodeParser.STRONG_TAG;
    else
      @tags['i'] = BBCodeParser.DEFAULT_TAGS['i'];
      @tags['b'] = BBCodeParser.DEFAULT_TAGS['b'];

  findTag: (name) ->
    name = name.toLowerCase();
    if (name of @tags)
      return @tags[name];
    else
      return null
  #
  # Parses the input string into a "BBDOM".
  #
  parse: (str) ->
    null

  transform: (str) ->
    str ?= "null"
    str = str.toString()
    tokenizer = new TagTokenizer(str)
    result = "";
    tagStack = [];
    top = null;
    while tokenizer.hasNext()
      tok = tokenizer.next()
      if (tok.type == 'tag')
        # Look up the tag.
        tag = @findTag(tok.name)
        if (tag)
          tag = @tags[tok.name]
          if (tag.nests)
            # Push onto the tag stack
            top = { name: tok.name, tag: tag }
            tagStack.push(top)
          html = tag.startTag(tok.name, tok.arg)
          result += html if html?
          if !tag.nests
            # In this case, keep on eating tokens until we find
            # a matching end tag.
            content = "";
            while tokenizer.hasNext()
              nestedTok = tokenizer.next()
              if (nestedTok.type == 'text')
                content += nestedTok.text;
              else if (nestedTok.type == 'endtag')
                if (nestedTok.name == tok.name)
                  # End tag - give the content over
                  result += tag.content(content)
                  # And end the tag
                  tag.endTag(nestedTok.name, nestedTok.arg)
                  break;
                else
                  # Add raw
                  content += nestedTok.raw
              else
                content += nestedTok.raw
        else
          # Don't understand it, dump it as-is.
          result += escapeHTML(tok.raw);
      else if (tok.type == 'endtag')
        # Currently this must be the top tag on the stack or we ignore
        # it.
        if (top && top.name == tok.name)
          html = top.tag.endTag(tok.name, tok.arg)
          result += html if html?
          # Pop the stack
          tagStack.pop()
          if (tagStack.length <= 0)
            top = null
          else
            top = tagStack[tagStack.length-1]
        else
          # Dump.
          result += escapeHTML(tok.raw)
      else if (tok.type == 'text')
        result += escapeHTML(tok.text)
    return convertNewlinesToHTML(result)

defaultParser = new BBCodeParser()

bbcode = (str) ->
  defaultParser.transform(str)

bbcode.escapeHTML = escapeHTML;
bbcode.escapeHTMLAttr = escapeHTMLAttr;

exports.bbcode = bbcode;
exports.Tag = Tag;
exports.BBCodeParser = BBCodeParser;

if (module.parent == null)
  # called directly, translate input files into HTML
  files = [];
  # TODO (maybe): Parse args
  for i in [2..process.argv.length]
    files.push(process.argv[i])
  fs = require('fs');
  files.forEach (f) ->
    # bbcode(fs.readFileSync(f))
    process.stdout.write(bbcode(fs.readFileSync(f)))
