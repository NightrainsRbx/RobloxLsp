"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.deactivate = exports.activate = void 0;
const vscode = require("vscode");
const languageserver = require("./languageserver");
const fetch = require("node-fetch");
const path = require("path");
const fs = require("fs");
const fetchData = (url, handler, resolve) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        fetch.default(url)
            .then(res => res.text())
            .then(body => handler(body))
            .then(resolve);
    }
    catch (err) {
        vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
        if (resolve != undefined) {
            resolve();
        }
    }
});
function writeToFile(path, content) {
    try {
        fs.writeFileSync(path, content);
    }
    catch (err) {
        vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
    }
}
function updateRobloxAPI(context) {
    fetchData('https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/version.txt', (lastVersion) => {
        try {
            const currentVersion = fs.readFileSync(context.asAbsolutePath(path.join('server', 'api', 'version.txt')), 'utf8');
            if (currentVersion != lastVersion) {
                vscode.window.withProgress({
                    location: vscode.ProgressLocation.Notification,
                    title: 'Roblox LSP: Updating API',
                    cancellable: false
                }, () => __awaiter(this, void 0, void 0, function* () {
                    return Promise.all([
                        new Promise(resolve => {
                            fetchData('https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json', (data) => {
                                writeToFile(context.asAbsolutePath(path.join('server', 'api', 'API-Dump.json')), data);
                            }, resolve);
                        }),
                        new Promise(resolve => {
                            fetchData('https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/api-docs/en-us.json', (data) => {
                                writeToFile(context.asAbsolutePath(path.join('server', 'api', 'API-Docs.json')), data);
                                resolve();
                            });
                        })
                    ]);
                })).then(() => {
                    vscode.window.showInformationMessage(`Roblox LSP: Updated API (${lastVersion}). [View changes](https://maximumadhd.github.io/Roblox-API-History)`, "Reload VSCode").then((item) => __awaiter(this, void 0, void 0, function* () {
                        if (item == "Reload VSCode") {
                            vscode.commands.executeCommand('workbench.action.reloadWindow');
                        }
                    }));
                });
                writeToFile(context.asAbsolutePath(path.join('server', 'api', 'version.txt')), lastVersion);
            }
        }
        catch (err) {
            vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
        }
    });
}
function openUpdatesWindow(context) {
    return __awaiter(this, void 0, void 0, function* () {
        if (context.globalState.get("sawVersionLogNew14", false) == false) {
            const panel = vscode.window.createWebviewPanel('robloxlspUpdates', 'Roblox LSP Updates', vscode.ViewColumn.One, {});
            panel.webview.html = `<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body>
            <div style="position:relative; padding-left:100px; padding-right:100px">
                <center><img src="https://i.imgur.com/PH5u9QD.png", witdh="300" height="300"></center>
                <h1 style="font-size:3rem; font-weight:100">Roblox LSP Release Notes!</h1>
                <p style="font-size:1rem">More info: <a href="https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745">https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745</a></p>
                <p style="font-size:1rem">Report any bug or question here: <a href="https://github.com/NightrainsRbx/RobloxLsp/issues">https://github.com/NightrainsRbx/RobloxLsp/issues</a></p>
                <hr style="height:2px;border:none;color:#333;background-color:#333;"/>
                <h2 style="font-size:2rem; font-weight:100">v1.5.7</h2>
                <li style="font-size:1rem">Syntax support for boolean singleton types.</li>
                <li style="font-size:1rem">Syntax support for default type parameters.</li>
                <li style="font-size:1rem">Added Vector2 and CFrame constants (thanks to <a href="https://github.com/ykh09242">@ykh09242</a>, <a href="https://github.com/NightrainsRbx/RobloxLsp/pull/145">#150</a>)</li>
                <li style="font-size:1rem">Added task.cancel and coroutine.close (thanks to <a href="https://github.com/Baileyeatspizza">@Baileyeatspizza</a>, <a href="https://github.com/NightrainsRbx/RobloxLsp/pull/145">#151</a>)</li>
                <li style="font-size:1rem">By default, all rojo project files found will be loaded and merged into one, change robloxLsp.workspace.rojoProjectFile if you prefer to use a specific one.</li>
                <h2 style="font-size:2rem; font-weight:100">v1.5.6</h2>
                <li style="font-size:1rem">Improved syntax support for Luau.</li>
                <li style="font-size:1rem">Added basic syntax support for generic type packs and singleton types.</li>
                <li style="font-size:1rem">Implemented suggeted imports for modules (thanks to <a href="https://github.com/Corecii">@Corecii</a>, <a href="https://github.com/NightrainsRbx/RobloxLsp/pull/123">#123</a>)</li>
                <li style="font-size:1rem">Added Vector3 constants (thanks to <a href="https://github.com/aku-e">@aku-e</a>, <a href="https://github.com/NightrainsRbx/RobloxLsp/pull/145">#145</a>)</li>
                <li style="font-size:1rem">Color3.fromHex is no longer deprecated.</li>
                <li style="font-size:1rem">Fixed deprecated classes not having typings. (<a href="https://github.com/NightrainsRbx/RobloxLsp/issues/147">#147</a>)</li>
                <li style="font-size:1rem">Fixed embedded rojo projects not using their correct root name. (<a href="https://github.com/NightrainsRbx/RobloxLsp/issues/128">#128</a>)</li>
                <li style="font-size:1rem">Inlay hints are not displayed if the type is "none" or "any".</li>
                <li style="font-size:1rem">Fixed diagnostics for type aliases with the same names as built-in types.</li>
                <li style="font-size:1rem">Updated binaries.</li>
            </div>
        </body>
        </html>`;
            yield context.globalState.update("sawVersionLogNew14", true);
        }
    });
}
function activate(context) {
    try {
        if (vscode.extensions.getExtension("sumneko.lua") != undefined) {
            vscode.window.showErrorMessage("The extension [Lua](https://marketplace.visualstudio.com/items?itemName=sumneko.lua) by sumneko is enabled, please disable it so that Roblox LSP can work properly.");
        }
    }
    catch (err) {
        vscode.window.showErrorMessage(err);
    }
    // openUpdatesWindow(context);
    updateRobloxAPI(context);
    languageserver.activate(context);
}
exports.activate = activate;
function deactivate() {
    languageserver.deactivate();
}
exports.deactivate = deactivate;
//# sourceMappingURL=extension.js.map