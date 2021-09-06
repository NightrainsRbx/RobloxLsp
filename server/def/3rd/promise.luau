export type Promise.Status = string

export type Promise.Static = Readonly<{
    new: (
        executor: (
            resolve: function,
            reject: function,
            onCancel: (abortHandler: function?) -> boolean
        ) -> ()
    ) -> Promise,
    defer: (
        deferExecutor: (
            resolve: function,
            reject: function,
            onCancel: (abortHandler: function?) -> boolean
        ) -> ()
    ) -> Promise,
    try: (callback: function, ...any) -> Promise,
    promisify: (callback: function) -> function,
    resolve: (value: any, ...any) -> Promise,
    reject: (value: any, ...any) -> Promise,
    all: (promises: Array<Promise>) -> Promise,
    allSettled: (promises: Array<Promise>) -> Promise,
    race: (promises: Array<Promise>) -> Promise,
    some: (promises: Array<Promise>, count: number) -> Promise,
    any: (promises: Array<Promise>) -> Promise,
    delay: (seconds: number) -> Promise,
    fold: (
        list: Array<Promise | any>,
        reducer: (
            accumulator: any,
            value: any,
            index: number
        ) -> (Promise | any),
        initialValue: any
    ) -> Promise,
    each: (
        list: Array<Promise | any>,
        predicate: (
            value: any,
            index: number
        ) -> (Promise | any)
    ) -> Promise,
    retry: (
        callback: (...any) -> Promise,
        times: number,
        ...any
    ) -> Promise,
    fromEvent: (
        event: RBXScriptSignal | {Connect: function},
        predicate: ((...any) -> boolean)?
    ) -> Promise,
    is: (object: any) -> boolean, -- This will be a type predicate in the future
    Status: Readonly<{
        Started: Promise.Status,
        Resolved: Promise.Status,
        Rejected: Promise.Status,
        Cancelled: Promise.Status
    }>
}>

export type Promise = Readonly<{
    andThen: (self: Promise, successHandler: function, failureHandler: function?) -> Promise,
    catch: (self: Promise, failureHandler: function) -> Promise,
    tap: (self: Promise, tapHandler: function) -> Promise,
    finally: (self: Promise, finallyHandler: (status: Promise.Status) -> ...any) -> Promise,
    done: (self: Promise, doneHandler: (status: Promise.Status) -> ...any) -> Promise,
    andThenCall: (self: Promise, callback: function, ...any) -> Promise,
    finallyCall: (self: Promise, callback: function, ...any) -> Promise,
    doneCall: (self: Promise, callback: function, ...any) -> Promise,
    andThenReturn: (self: Promise, ...any) -> Promise,
    finallyReturn: (self: Promise, ...any) -> Promise,
    doneReturn: (self: Promise, ...any) -> Promise,
    timeout: (self: Promise, seconds: number, rejectionValue: any?) -> Promise,
    cancel: (self: Promise) -> (),
    now: (self: Promise, rejectionValue: any?) -> Promise,
    await: (self: Promise) -> (boolean, ...any),
    awaitStatus: (self: Promise) -> (Promise.Status, ...any),
    expect: (self: Promise) -> ...any,
    getStatus: (self: Promise) -> Promise.Status
}>