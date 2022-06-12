export type Roact.Binding = {
    getValue: (self: Roact.Binding) -> any,
    map: (self: Roact.Binding, mappingFunction: (value: any) -> any) -> Roact.Binding
}

export type Roact.Element = {
    component:
        string
        | Roact.Component
        | (props: table) -> Roact.Element,
    props: table,
    source: string?
}

export type Roact.Fragment = Roact.Element

export type Roact.Symbol = symbol

export type Roact.Ref = {
    [any]: any,
    getValue: (self: Roact.Ref) -> any
}

export type Roact.Tree = symbol

export type Roact.Component = {
    [any]: any,
    extend: (self: Roact.Component, name: string) -> Roact.Component,
    defaultProps: table,
    props: table,
    state: table,
    init: (self: Roact.Component, initialProps: table) -> (),
    render: (self: Roact.Component) -> Roact.Element?,
    setState:
        ((self: Roact.Component, stateChange: table) -> ())
        & ((self: Roact.Component, stateUpdater: (
                prevState: table,
                props: table
            ) -> table) -> ()),
    shouldUpdate: (self: Roact.Component, nextProps: table, nextState: table) -> boolean,
    validateProps: (props: table) -> (boolean, string?),
    getElementTraceback: (self: Roact.Component) -> string?,
    didMount: (self: Roact.Component) -> (),
    willUnmount: (self: Roact.Component) -> (),
    willUpdate: (self: Roact.Component, nextProps: table, nextState: table) -> (),
    didUpdate: (self: Roact.Component, previousProps: table, previousState: table) -> (),
    getDerivedStateFromProps: (nextProps: table, lastState: table) -> table,
}

export type Roact = {
    ---@special Roact.createElement
    createElement: (
        component:
            string
            | Roact.Component
            | (props: table) -> Roact.Element,
        props: table?,
        children: { [string | number]: Roact.Element }?
    ) -> Roact.Element,
    createFragment: (elements: { [string | number]: Roact.Element }) -> Roact.Fragment,
    mount: (element: Roact.Element, parent: Instance?, key: string?) -> Roact.Tree,
    update: (tree: Roact.Tree, element: Roact.Element) -> Roact.Tree,
    unmount: (tree: Roact.Tree) -> (),
    oneChild: (children: { [string | number]: Roact.Element }?) -> Roact.Element?,
    createBinding: (initialValue: any) -> (Roact.Binding, (newValue: any) -> ()),
    joinBindings: (bindings: { [string | number]: Roact.Binding }) -> Roact.Binding,
    createRef: () -> Roact.Ref,
    forwardRef: (render: (props: table, ref: Roact.Ref) -> Roact.Element) -> Roact.Component,
    createContext: (defaultValue: any) -> {
        Provider: Roact.Component,
        Consumer: Roact.Component
    },
    setGlobalConfig: (configValues: {
        typeChecks: boolean?,
        internalTypeChecks: boolean?,
        elementTracing: boolean?,
        propValidation: boolean?
    }) -> (),

    Children: Roact.Symbol,
    Ref: Roact.Symbol,
    ---@special Roact.Event
    Event: { [string]: Roact.Symbol },
    ---@special Roact.Change
    Change: { [string]: Roact.Symbol },
    None: Roact.Symbol,

    Component: Roact.Component,
    PureComponent: Roact.Component,
    Portal: Roact.Component
}