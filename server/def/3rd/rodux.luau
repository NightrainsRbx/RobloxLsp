export type Rodux.Reducer = (state: any, action: table) -> any

export type Rodux.Middleware = (nextDispatch: function, store: any) -> (action: any) -> any

type Signal<C> = {
    connect: (self: Signal<C>, listener: C) -> {disconnect: function}
}

export type Rodux.Store = {
    changed: Signal<(newState: any, oldState: any) -> ()>,
    dispatch: (self: Rodux.Store, action: table) -> nil,
    getState: (self: Rodux.Store) -> any,
    destruct: (self: Rodux.Store) -> nil,
    flush: (sefl: Rodux.Store) -> nil
}>

export type Rodux = {
    Store: {new: (reducer: Rodux.Reducer, initialState: any?, middlewares: Array<Rodux.Middleware>) -> Rodux.Store},
    combineReducers: (map: {[any]: Rodux.Reducer}) -> Rodux.Reducer,
    createReducer: (initialState: any, actionHandlers: {[any]: Rodux.Reducer}) -> Rodux.Reducer,
    makeActionCreator: (name: string, actionGeneratorFunction: function) -> any,
    loggerMiddleware: Rodux.Middleware,
    thunkMiddleware: Rodux.Middleware
}