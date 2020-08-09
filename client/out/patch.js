'use strict';
Object.defineProperty(exports, "__esModule", { value: true });

let code = require("vscode");
let realMarkdownString = code.MarkdownString

function patchedMarkdownString(value, supportThemeIcons) {
    let ms = new realMarkdownString(value, supportThemeIcons);
    this.value = ms.value;
    this.supportThemeIcons = ms.supportThemeIcons;
    this.isTrusted = true;
    this.prototype = ms.prototype;
}

function patchMarkdown() {
    code.MarkdownString = patchedMarkdownString;
}

function patch(client) {
    patchMarkdown();
}

exports.patch = patch
