import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import {
    workspace as Workspace,
    ExtensionContext,
    env as Env,
    commands as Commands,
    TextDocument,
    WorkspaceFolder,
    Uri,
} from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    DocumentSelector,
} from 'vscode-languageclient/node';

let defaultClient: LanguageClient;
let clients: Map<string, LanguageClient> = new Map();

function registerCustomCommands(context: ExtensionContext) {
    context.subscriptions.push(Commands.registerCommand('lua.config', (data) => {
        let config = Workspace.getConfiguration(undefined, Uri.parse(data.uri));
        if (data.action == 'add') {
            let value: any[] = config.get(data.key);
            value.push(data.value);
            config.update(data.key, value);
            return;
        }
        if (data.action == 'set') {
            config.update(data.key, data.value);
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

function start(context: ExtensionContext, documentSelector: DocumentSelector, folder: WorkspaceFolder): LanguageClient {
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
    let develop: boolean = config.get("Lua.develop.enable");
    let debuggerPort: number = config.get("Lua.develop.debuggerPort");
    let debuggerWait: boolean = config.get("Lua.develop.debuggerWait");
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
            '-e',
            `DEVELOP=${develop};DBGPORT=${debuggerPort};DBGWAIT=${debuggerWait}`,
            context.asAbsolutePath(path.join(
                'server',
                'main.lua',
            ))
        ]
    };

    let client = new LanguageClient(
        'Lua',
        'Lua',
        serverOptions,
        clientOptions
    );

    client.registerProposedFeatures();
    client.start();

    return client;
}

export function activate(context: ExtensionContext) {
    registerCustomCommands(context);
    function didOpenTextDocument(document: TextDocument): void {
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
            let client = start(context, [
                { scheme: 'file', language: 'lua', pattern: `${folder.uri.fsPath}/**/*` }
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
    let promises: Thenable<void>[] = [];
    if (defaultClient) {
        promises.push(defaultClient.stop());
    }
    for (let client of clients.values()) {
        promises.push(client.stop());
    }
    return Promise.all(promises).then(() => undefined);
}
