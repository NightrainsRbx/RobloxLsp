type ENV = {
    describe: (phrase: string, callback: (context: table) -> ()) -> (),
    it: (phrase: string, callback: (context: table) -> ()) -> (),
    expect: (value: any) -> Keys,
    afterAll: (callback: (context: table) -> ()) -> (),
    afterEach: (callback: (context: table) -> ()) -> (),
    beforeAll: (callback: (context: table) -> ()) -> (),
    beforeEach: (callback: (context: table) -> ()) -> (),
    FIXME: (optionalMessage: string?) -> (),
    FOCUS: () -> (),
    SKIP: () -> (),
    describeFOCUS: (phrase: string, callback: (context: table) -> ()) -> (),
    describeSKIP: (phrase: string, callback: (context: table) -> ()) -> (),
    itFOCUS: (phrase: string, callback: (context: table) -> ()) -> (),
    itSKIP: (phrase: string, callback: (context: table) -> ()) -> (),
    itFIXME: (phrase: string, callback: (context: table) -> ()) -> ()
}

type Expectation = {
    a: (typeName: string) -> Expectation,
    an: (typeName: string) -> Expectation,
    ok: () -> Expectation,
    equal: (otherValue: any) -> Expectation,
    throw: (message: string?) -> Expectation,
    near: (otherValue: number, limit: number?) -> Expectation
}

type Keys = {
    to: Expectation & Keys,
    be: Expectation & Keys,
    been: Expectation & Keys,
    have: Expectation & Keys,
    was: Expectation & Keys,
    at: Expectation & Keys,
    never: Expectation & Keys
}