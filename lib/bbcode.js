/**
 * Module for dealing with BBcode.
 * This module is extensible, allowing "new" BBCode to be added.
 * Tags may optionally take an argument, and closing tags may optionally require
 * the closing argument to match. (So [list=1][/list=1] versus [list=1][/list])
 */

/**
 * Very basic tag class that simply generates HTML.
 * @param {String} html the HTML tag to generate for the start/end tags.
 */
function Tag(html) {
	this.html_start = "<" + html + ">";
	this.html_end = "</" + html + ">";
}

Tag.prototype = {
	/**
	 * Whether or not this tag "nests" with other tags - if false, everything
	 * before its ending tag will be passed to content. Otherwise, subtags will
	 * be parsed.
	 */
	nests: true,
	startTag: function(name, arg) {
		return this.html_start;
	},
	/**
	 * Receive the tag content. If "nests" is true, this is ONLY called for
	 * text that passes through it before being given to other tags.
	 */
	content: function(str) {
		return str;
	},
	endTag: function(name, arg) {
		return this.html_end;
	}
};

function URLTag() {
}

URLTag.prototype = new Tag("a");
URLTag.prototype.startTag = function(name, arg) {
	return '<a href="' + escapeHTMLAttr(arg) + '" rel="nofollow">';
};

function ImgTag() {
}

ImgTag.prototype = new Tag("img");
ImgTag.prototype.nests = false;
ImgTag.prototype.startTag = function(name, arg) {
	// Do nothing.
};
ImgTag.prototype.content = function(str) {
	return '<img src="' + str + '">';
};
ImgTag.prototype.endTag = function(name, arg) {
	// Also do nothing
};

function escapeHTML(str) {
	return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function escapeHTMLAttr(str) {
	return escapeHTML(str).replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function convertNewlinesToHTML(text) {
	text = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").replace(/\n/g, "<br>\n").replace(/<br>\n<br>\n/g, "</p>\n\n<p>");
	return '<p>' + text + '</p>';
}

function TagTokenizer(str) {
	this.str = str;
	this.currentOffset = 0;
	this.nextToken = this._next();
}

TagTokenizer.prototype = {
	/**
	 * Determines if the text is a valid tag (allowed between [ and ])
	 */
	isValidTag: function(tag) {
		return /^\/?[A-Za-z]+(?:=[^\]]*|="[^"]*")?$/.test(tag);
	},
	hasNext: function() {
		return this.nextToken != null;
	},
	/**
	 */
	next: function() {
		if (this.nextToken == null)
			throw Error("No more tokens");
		var result = this.nextToken;
		if (this.nextToken.type == 'text') {
			// Merge text tokens if there are any
			var nextNext;
			for (nextNext = this._next(); nextNext != null && nextNext.type == 'text'; nextNext = this._next()) {
				result.text += nextNext.text;
			}
			this.nextToken = nextNext;
		} else {
			this.nextToken = this._next();
		}
		if (result.type == 'tag' && result.name.charAt(0) == '/') {
			result.name = result.name.substring(1);
			result.type = 'endtag';
		}
		return result;
	},
	/**
	 * Internal implementation of next, before multiple text tokens are merged.
	 */
	_next: function() {
		//console.log("_next(%d)", this.currentOffset);
		if (this.currentOffset >= this.str.length)
			return null;
		// This is fairly simple: are we starting with a [?
		if (this.str.charAt(this.currentOffset) == '[') {
			// Assume this is a tag for now
			var idx = this.str.indexOf(']', this.currentOffset);
			if (idx < 0) {
				// Last token! Because we can never find an end tag
				var tok = { type: 'text', text: this.str.substring(this.currentOffset) };
				this.currentOffset = this.str.length;
				return tok;
			}
			// Otherwise, grab the contents as a tag, maybe
			var tag = this.str.substring(this.currentOffset+1, idx);
			// Is this a real tag?
			if (this.isValidTag(tag)) {
				// OK - now we split it into a tag and an argument (if any)
				var name = tag;
				var arg = null;
				var eqIdx = tag.indexOf('=');
				if (eqIdx >= 0) {
					name = tag.substring(0, eqIdx);
					arg = tag.substring(eqIdx + 1);
					// If the argument is surrounded by quotes, remove them
					if (arg.charAt(0) == '"' && arg.charAt(arg.length-1) == '"') {
						arg.substring(1, arg.length-1);
					}
				}
				var raw = this.str.substring(this.currentOffset, idx+1);
				this.currentOffset = idx+1;
				// Always canonicalize the tokenized name to lower case
				return { type: 'tag', name: name.toLowerCase(), arg: arg, raw: raw };
			} else {
				// We don't like this tag, so we just return the current text
				// element, advance by one, and continue.
				this.currentOffset++;
				return { type: 'text', text: '[' };
			}
		} else {
			var idx = this.str.indexOf('[', this.currentOffset);
			if (idx < 0) {
				// last text token
				var tok = { type: 'text', text: this.str.substring(this.currentOffset) };
				this.currentOffset = this.str.length;
				return tok;
			} else {
				var tok = { type: 'text', text: this.str.substring(this.currentOffset, idx) };
				this.currentOffset = idx;
				return tok;
			}
		}
	}
};

function BBCodeParser() {
}

BBCodeParser.prototype = {
	tags: {
		'url': new URLTag(),
		'img': new ImgTag(),
		'b': new Tag('b'),
		'i': new Tag('i'),
		'u': new Tag('u'),
		's': new Tag('strike')
	},
	findTag: function(name) {
		name = name.toLowerCase();
		if (name in this.tags) {
			return this.tags[name];
		} else {
			return null;
		}
	},
	transform: function(str) {
		str = str.toString();
		var tokenizer = new TagTokenizer(str);
		var result = "";
		var tagStack = [];
		var top = null;
		while (tokenizer.hasNext()) {
			var tok = tokenizer.next();
			if (tok.type == 'tag') {
				// Look up the tag.
				var tag = this.findTag(tok.name);
				if (tag) {
					var tag = this.tags[tok.name];
					if (tag.nests) {
						// Push onto the tag stack
						top = { name: tok.name, tag: tag };
						tagStack.push(top);
					}
					var html = tag.startTag(tok.name, tok.arg);
					if (html)
						result += html;
					if (!tag.nests) {
						// In this case, keep on eating tokens until we find
						// a matching end tag.
						var content = "";
						while (tokenizer.hasNext()) {
							var nestedTok = tokenizer.next();
							if (nestedTok.type == 'text')
								content += nestedTok.text;
							else if (nestedTok.type == 'endtag') {
								if (nestedTok.name == tok.name) {
									// End tag - give the content over
									result += tag.content(content);
									// And end the tag
									tag.endTag(nestedTok.name, nestedTok.arg);
									break;
								} else {
									// Add raw
									content += nestedTok.raw;
								}
							} else {
								content += nestedTok.raw;
							}
						}
					}
				} else {
					// Don't understand it, dump it as-is.
					result += escapeHTML(tok.raw);
				}
			} else if (tok.type == 'endtag') {
				// Currently this must be the top tag on the stack or we ignore
				// it.
				if (top && top.name == tok.name) {
					var html = top.tag.endTag(tok.name, tok.arg);
					if (html)
						result += html;
					// Pop the stack
					tagStack.pop();
					if (tagStack.length <= 0) {
						top = null;
					} else {
						top = tagStack[tagStack.length-1];
					}
				} else {
					// Dump.
					result += escapeHTML(tok.raw);
				}
			} else if (tok.type == 'text') {
				result += escapeHTML(tok.text);
			}
		}
		return convertNewlinesToHTML(result);
	}
};

var defaultParser = new BBCodeParser();

function bbcode(str) {
	return defaultParser.transform(str);
}

bbcode.escapeHTML = escapeHTML;
bbcode.escapeHTMLAttr = escapeHTMLAttr;

exports.bbcode = bbcode;
exports.Tag = Tag;
exports.BBCodeParser = BBCodeParser;

if (module.parent == null) {
	// called directly, translate input files into HTML
	var files = [];
	// TODO (maybe): Parse args
	for (var i = 2; i < process.argv.length; i++) {
		files.push(process.argv[i]);
	}
	var fs = require('fs');
	files.forEach(function(f) {
		//	bbcode(fs.readFileSync(f))
		process.stdout.write(bbcode(fs.readFileSync(f)));
	});
}
