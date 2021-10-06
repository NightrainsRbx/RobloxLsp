import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import * as vscode from 'vscode';
import * as types from 'vscode-languageserver-types';
import {
    workspace as Workspace,
    ExtensionContext,
    env as Env,
    commands as Commands,
    TextDocument,
    WorkspaceFolder,
    Uri,
    window,
    TextEditor,
} from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    DocumentSelector,
} from 'vscode-languageclient/node';

import * as express from 'express';
import { Server } from 'http';

let defaultClient: LanguageClient;
let clients: Map<string, LanguageClient> = new Map();

function registerCustomCommands(context: ExtensionContext) {
    context.subscriptions.push(Commands.registerCommand('lua.config', (data) => {
        let config = Workspace.getConfiguration(undefined, Uri.parse(data.uri));
        if (data.action == 'add') {
            let value: any[] = config.get(data.key);
            value.push(data.value);
            config.update(data.key, value, data.global);
            return;
        }
        if (data.action == 'set') {
            config.update(data.key, data.value, data.global);
            return;
        }
    }))
}

let _sortedWorkspaceFolders: string[] | undefined;
function sortedWorkspaceFolders(): string[] {
    if (_sortedWorkspaceFolders === void 0) {
        _sortedWorkspaceFolders = Workspace.workspaceFolders ? Workspace.workspaceFolders.map(folder => {
            let result = folder.uri.toString();
            if (result.charAt(result.length - 1) !== '/') {
                result = result + '/';
            }
            return result;
        }).sort(
            (a, b) => {
                return a.length - b.length;
            }
        ) : [];
    }
    return _sortedWorkspaceFolders;
}
Workspace.onDidChangeWorkspaceFolders(() => _sortedWorkspaceFolders = undefined);

function getOuterMostWorkspaceFolder(folder: WorkspaceFolder): WorkspaceFolder {
    let sorted = sortedWorkspaceFolders();
    for (let element of sorted) {
        let uri = folder.uri.toString();
        if (uri.charAt(uri.length - 1) !== '/') {
            uri = uri + '/';
        }
        if (uri.startsWith(element)) {
            return Workspace.getWorkspaceFolder(Uri.parse(element))!;
        }
    }
    return folder;
}

function start(context: ExtensionContext, documentSelector: DocumentSelector, folder: WorkspaceFolder) {
    // Options to control the language client
    let clientOptions: LanguageClientOptions = {
        // Register the server for plain text documents
        documentSelector: documentSelector,
        workspaceFolder: folder,
        progressOnInitialization: true,
        markdown: {
            isTrusted: true,
        },
    };

    let config = Workspace.getConfiguration(undefined, folder);
    let develop: boolean = config.get("robloxLsp.develop.enable");
    let debuggerPort: number = config.get("robloxLsp.develop.debuggerPort");
    let debuggerWait: boolean = config.get("robloxLsp.develop.debuggerWait");
    let commandParam: string = config.get("robloxLsp.misc.parameters");
    let command: string;
    let platform: string = os.platform();
    switch (platform) {
        case "win32":
            command = context.asAbsolutePath(
                path.join(
                    'server',
                    'bin',
                    'Windows',
                    'lua-language-server.exe'
                )
            );
            break;
        case "linux":
            command = context.asAbsolutePath(
                path.join(
                    'server',
                    'bin',
                    'Linux',
                    'lua-language-server'
                )
            );
            fs.chmodSync(command, '777');
            break;
        case "darwin":
            command = context.asAbsolutePath(
                path.join(
                    'server',
                    'bin',
                    'macOS',
                    'lua-language-server'
                )
            );
            fs.chmodSync(command, '777');
            break;
    }

    let serverOptions: ServerOptions = {
        command: command,
        args: [
            '-E',
            context.asAbsolutePath(path.join(
                'server',
                'main.lua',
            )),
            `--develop=${develop}`,
            `--dbgport=${debuggerPort}`,
            `--dbgwait=${debuggerWait}`,
            commandParam,
        ]
    };

    let client = new LanguageClient(
        'Lua',
        'Lua',
        serverOptions,
        clientOptions
    );

    // client.registerProposedFeatures();
    client.start();
    client.onReady().then(() => {
        onCommand(client);
        onDecorations(client);
        statusBar(client);
        startPluginServer(client);
    });

    return client;
}

let server: Server | undefined;
function startPluginServer(client: LanguageClient) {
    try {
        let lastUpdate = "";
        let app = express();
        app.use('/update', express.json({
            limit: '1mb',
        }));
        app.post('/update', async (req, res) => {
            if (!req.body) {
                res.status(400);
                res.json({
                    success: false,
                    reason: 'Missing JSON',
                });
                return;
            }
            if (!req.body.DataModel) {
                res.status(400);
                res.json({
                    success: false,
                    reason: 'Missing body.DataModel',
                });
                return;
            }
            try {
                client.sendNotification('$/updateDataModel', {
                    "datamodel": req.body.DataModel,
                    "version": req.body.Version
                });
                lastUpdate = req.body.DataModel;
            } catch (err) {
                vscode.window.showErrorMessage(err);
            }
            res.status(200);
            res.json({success: true});
        });
        app.get("/last", (req, res) => {
            res.send(lastUpdate);
        });
        let port = vscode.workspace.getConfiguration().get("robloxLsp.misc.serverPort");
        if (port > 0) {
            server = app.listen(port, () => {
                // vscode.window.showInformationMessage(`Started Roblox LSP Plugin Server on port ${port}`);
            });
        }
    } catch (err) {
        vscode.window.showErrorMessage(`Failed to launch Roblox LSP plugin server: ${err}`);
    }
}

let barCount = 0;
function statusBar(client: LanguageClient) {
    let bar = window.createStatusBarItem();
    bar.text = 'Roblox LSP';
    barCount ++;
    bar.command = 'Lua.statusBar:' + barCount;
    Commands.registerCommand(bar.command, () => {
        client.sendNotification('$/status/click');
    })
    client.onNotification('$/status/show', (params) => {
        bar.show();
    })
    client.onNotification('$/status/hide', (params) => {
        bar.hide();
    })
    client.onNotification('$/status/report', (params) => {
        bar.text    = params.text;
        bar.tooltip = params.tooltip;
    })
}

function onCommand(client: LanguageClient) {
    client.onNotification('$/command', (params) => {
        Commands.executeCommand(params.command, params.data);
    });
}

function isDocumentInClient(textDocuments: TextDocument, client: LanguageClient): boolean {
    let selectors = client.clientOptions.documentSelector;
    if (!DocumentSelector.is(selectors)) {{
        return false;
    }}
    if (vscode.languages.match(selectors, textDocuments)) {
        return true;
    }
    return false;
}

function onDecorations(client: LanguageClient) {
    let textType = window.createTextEditorDecorationType({})

    function notifyVisibleRanges(textEditor: TextEditor) {
        if (!isDocumentInClient(textEditor.document, client)) {
            return;
        }
        let uri:    types.DocumentUri = client.code2ProtocolConverter.asUri(textEditor.document.uri);
        let ranges: types.Range[] = [];
        for (let index = 0; index < textEditor.visibleRanges.length; index++) {
            const range = textEditor.visibleRanges[index];
            ranges[index] = client.code2ProtocolConverter.asRange(new vscode.Range(
                Math.max(range.start.line - 3, 0),
                range.start.character,
                Math.min(range.end.line + 3, textEditor.document.lineCount - 1),
                range.end.character
            ));
        }
        for (let index = ranges.length; index > 1; index--) {
            const current = ranges[index];
            const before = ranges[index - 1];
            if (current.start.line > before.end.line) {
                continue;
            }
            if (current.start.line == before.end.line && current.start.character > before.end.character) {
                continue;
            }
            ranges.pop();
            before.end = current.end;
        }
        client.sendNotification('$/didChangeVisibleRanges', {
            uri:    uri,
            ranges: ranges,
        })
    }

    for (let index = 0; index < window.visibleTextEditors.length; index++) {
        notifyVisibleRanges(window.visibleTextEditors[index]);
    }

    window.onDidChangeVisibleTextEditors((params: TextEditor[]) => {
        for (let index = 0; index < params.length; index++) {
            notifyVisibleRanges(params[index]);
        }
    })

    window.onDidChangeTextEditorVisibleRanges((params: vscode.TextEditorVisibleRangesChangeEvent) => {
        notifyVisibleRanges(params.textEditor);
    })

    client.onNotification('$/hint', (params) => {
        let uri:        types.URI = params.uri;
        for (let index = 0; index < window.visibleTextEditors.length; index++) {
            const editor = window.visibleTextEditors[index];
            if (editor.document.uri.toString() == uri && isDocumentInClient(editor.document, client)) {
                let textEditor = editor;
                let edits:  types.TextEdit[] = params.edits
                let options: vscode.DecorationOptions[] = [];
                for (let index = 0; index < edits.length; index++) {
                    const edit = edits[index];
                    options[index] = {
                        hoverMessage:  edit.newText,
                        range:         client.protocol2CodeConverter.asRange(edit.range),
                        renderOptions: {
                            light: {
                                after: {
                                    contentText:     edit.newText,
                                    color:           '#888888',
                                    backgroundColor: '#EEEEEE;border-radius: 4px; padding: 0px 2px;',
                                    fontWeight:      '400; font-size: 12px; line-height: 1;',
                                }
                            },
                            dark: {
                                after: {
                                    contentText:     edit.newText,
                                    color:           '#888888',
                                    backgroundColor: '#333333;border-radius: 4px; padding: 0px 2px;',
                                    fontWeight:      '400; font-size: 12px; line-height: 1;',
                                }
                            }
                        }
                    }
                }
                textEditor.setDecorations(textType, options);
            }
        }
    })
    
    let textType2 = window.createTextEditorDecorationType({opacity: "0.5",})
    client.onNotification('$/luaComment', (params) => {
        let uri:        types.URI = params.uri;
        for (let index = 0; index < window.visibleTextEditors.length; index++) {
            const editor = window.visibleTextEditors[index];
            if (editor.document.uri.toString() == uri && isDocumentInClient(editor.document, client)) {
                let ranges: vscode.Range[] = params.ranges
                let options: vscode.DecorationOptions[] = [];
                for (let index = 0; index < ranges.length; index++) {
                    options[index] = {range: ranges[index]}
                }
                editor.setDecorations(textType2, options);
            }
        }
    })
}

export function activate(context: ExtensionContext) {
    registerCustomCommands(context);
    function didOpenTextDocument(document: TextDocument) {
        // We are only interested in language mode text
        if (document.languageId !== 'lua' || (document.uri.scheme !== 'file' && document.uri.scheme !== 'untitled')) {
            return;
        }

        let uri = document.uri;
        let folder = Workspace.getWorkspaceFolder(uri);
        // Untitled files go to a default client.
        if (folder == null && Workspace.workspaceFolders == null && !defaultClient) {
            defaultClient = start(context, [
                { scheme: 'file', language: 'lua' }
            ], null);
            return;
        }

        // Files outside a folder can't be handled. This might depend on the language.
        // Single file languages like JSON might handle files outside the workspace folders.
        if (!folder) {
            return;
        }
        // If we have nested workspace folders we only start a server on the outer most workspace folder.
        folder = getOuterMostWorkspaceFolder(folder);

        if (!clients.has(folder.uri.toString())) {
            let pattern: string = folder.uri.fsPath.replace(/(\[|\])/g, '[$1]') + '/**/*';
            let client = start(context, [
                { scheme: 'file', language: 'lua', pattern: pattern }
            ], folder);
            clients.set(folder.uri.toString(), client);
        }
    }

    function didCloseTextDocument(document: TextDocument): void {
        let uri = document.uri;
        if (clients.has(uri.toString())) {
            let client = clients.get(uri.toString());
            if (client) {
                clients.delete(uri.toString());
                client.stop();
            }
        }
    }

    Workspace.onDidOpenTextDocument(didOpenTextDocument);
    //Workspace.onDidCloseTextDocument(didCloseTextDocument);
    Workspace.textDocuments.forEach(didOpenTextDocument);
    Workspace.onDidChangeWorkspaceFolders((event) => {
        for (let folder of event.removed) {
            let client = clients.get(folder.uri.toString());
            if (client) {
                clients.delete(folder.uri.toString());
                client.stop();
            }
        }
    });
}

export function deactivate(): Thenable<void> | undefined {
    if (server != undefined) {
        server.close();
        server = undefined;
    }
    let promises: Thenable<void>[] = [];
    if (defaultClient) {
        promises.push(defaultClient.stop());
    }
    for (let client of clients.values()) {
        promises.push(client.stop());
    }
    return Promise.all(promises).then(() => undefined);
}
