local testez = {}

function testez:generateLibs()
    local globals = {}
    globals.describe = {
        name = "describe",
        type = "function",
        args = {
            [1] = {
                name = "phrase",
                type = "string"
            },
            [2] = {
                name = "callback",
                type = "function",
                args = {
                    [1] = {
                        name = "context",
                        type = "table"
                    }
                }
            }
        },
        description = "This function creates a new ``describe`` block. These blocks correspond to the things that are being tested.\n\nPut ``it`` blocks inside of ``describe`` blocks to describe what behavior should be correct.",
        testez = true
    }
    globals.it = {
        name = "it",
        type = "function",
        args = {
            [1] = {
                name = "phrase",
                type = "string"
            },
            [2] = {
                name = "callback",
                type = "function",
                args = {
                    [1] = {
                        name = "context",
                        type = "table"
                    }
                }
            }
        },
        description = "This function creates a new 'it' block. These blocks correspond to the behaviors that should be expected of the thing you're testing.",
        testez = true
    }
    local expectation = {
        a = {
            name = "a",
            type = "function",
            args = {
                [1] = {
                    name = "typeName",
                    type = "string"
                }
            },
            enums = {
                [1] = {
                    name = "typeName",
                    enum = '"nil"'
                },
                [2] = {
                    name = "typeName",
                    enum = '"number"'
                },
                [3] = {
                    name = "typeName",
                    enum = '"string"'
                },
                [4] = {
                    name = "typeName",
                    enum = '"boolean"'
                },
                [5] = {
                    name = "typeName",
                    enum = '"table"'
                },
                [6] = {
                    name = "typeName",
                    enum = '"function"'
                },
                [7] = {
                    name = "typeName",
                    enum = '"thread"'
                },
                [8] = {
                    name = "typeName",
                    enum = '"userdata"'
                }
            },
            description = "Assert that the expectation value is the given type."
        },
        an = {
            name = "an",
            type = "function",
            description = "Assert that the expectation value is the given type. Alias for ``a``."
        },
        ok = {
            name = "ok",
            type = "function",
            description = "Assert that our expectation value is truthy."
        },
        equal = {
            name = "equal",
            type = "function",
            args = {
                [1] = {
                    name = "otherValue",
                    type = "any"
                }
            },
            description = "Assert that our expectation value is equal to another value."
        },
        throw = {
            name = "throw",
            type = "function",
            args = {
                [1] = {
                    name = "message",
                    type = "string",
                    optional = "self"
                }
            },
            description = "Assert that our function expectation value throws an error when called. An optional error message can be passed to assert that the error message contains the given value."
        },
        near = {
            name = "near",
            type = "function",
            args = {
                [1] = {
                    name = "otherValue",
                    type = "number"
                },
                [2] = {
                    name = "limit",
                    type = "number",
                    optional = "self"
                }
            },
            description = "Assert that our expectation value is equal to another value within some inclusive limit."
        }
    }
    expectation.an.args = expectation.a.args
    expectation.an.enums = expectation.a.enums
    for _, t in pairs(expectation) do
        t.returns = {
            [1] = {
                type = "Expectation",
                child = expectation
            }
        }
    end
    globals.expect = {
        name = "expect",
        type = "function",
        args = {
            [1] = {
                name = "value",
                type = "any"
            }
        },
        returns = {
            [1] = {
                type = "Expectation",
                child = {
                    to = {
                        name = "to",
                        type = "Expectation",
                        child = {
                            be = {
                                name = "be",
                                type = "Expectation",
                                child = expectation
                            },
                            never = {
                                name = "never",
                                type = "Expectation",
                                child = {
                                    be = {
                                        name = "be",
                                        type = "table",
                                        child = expectation
                                    }
                                }
                            }
                        }
                    },
                    never = {
                        name = "never",
                        type = "Expectation",
                        child = {
                            to = {
                                name = "to",
                                type = "Expectation",
                                child = {
                                    be = {
                                        name = "be",
                                        type = "Expectation",
                                        child = expectation
                                    }
                                }
                            }
                        }
                    },
                }
            }
        },
        description = "Creates a new ``Expectation``, used for testing the properties of the given value.",
        testez = true
    }
    globals.afterAll = {
        name = "afterAll",
        type = "function",
        args = {
            [1] = {
                name = "callback",
                type = "function",
                args = {
                    [1] = {
                        name = "context",
                        type = "table"
                    }
                }
            }
        },
        description = "Returns a function after all the tests within its scope run. This is useful if you want to clean up some global state that is used by other tests within its scope.",
        testez = true
    }
    globals.afterEach = {
        name = "afterEach",
        type = "function",
        args = {
            [1] = {
                name = "callback",
                type = "function",
                args = {
                    [1] = {
                        name = "context",
                        type = "table"
                    }
                }
            }
        },
        description = "Returns a function after each of the tests within its scope. This is useful if you want to cleanup some temporary state that is created by each test. It is always ran regardless of if the test failed or not.",
        testez = true
    }
    globals.beforeAll = {
        name = "beforeAll",
        type = "function",
        args = {
            [1] = {
                name = "callback",
                type = "function",
                args = {
                    [1] = {
                        name = "context",
                        type = "table"
                    }
                }
            }
        },
        description = "Runs a function before any of the tests within its scope run. This is useful if you want to set up state that will be used by other tests within its scope.",
        testez = true
    }
    globals.beforeEach = {
        name = "beforeEach",
        type = "function",
        args = {
            [1] = {
                name = "callback",
                type = "function",
                args = {
                    [1] = {
                        name = "context",
                        type = "table"
                    }
                }
            }
        },
        description = "Runs a function before each of the tests within its scope. This is useful if you want to reset global state that will be used by other tests within its scope.",
        testez = true
    }
    globals.FIXME = {
        name = "FIXME",
        type = "function",
        args = {
            [1] = {
                name = "optionalMessage",
                type = "string",
                optional = "self"
            }
        },
        description = "When called inside a ``describe`` block, ``FIXME`` is used to identify broken tests and marks the block as skipped.",
        testez = true
    }
    globals.FOCUS = {
        name = "FOCUS",
        type = "function",
        description = "When called inside a ``describe`` block, ``FOCUS()`` marks that block as focused. If there are any focused blocks inside your test tree, only focused blocks will be executed, and all other tests will be skipped.",
        testez = true
    }
    globals.SKIP = {
        name = "SKIP",
        type = "function",
        description = "This function works similarly to ``FOCUS()``, except instead of marking a block as focused, it will mark a block as skipped, which stops any of the test assertions in the block from being executed.",
        testez = true
    }
    globals.describeFOCUS = {
        name = "describeFOCUS",
        type = "function",
        args = {
            [1] = {
                name = "phrase",
                type = "string"
            }
        },
        testez = true
    }
    globals.describeSKIP = {
        name = "describeSKIP",
        type = "function",
        args = {
            [1] = {
                name = "phrase",
                type = "string"
            }
        },
        testez = true
    }
    globals.fdescribe = globals.describeFOCUS
    globals.xdescribe = globals.describeSKIP
    globals.itFOCUS = {
        name = "itFOCUS",
        type = "function",
        args = {
            [1] = {
                name = "phrase",
                type = "string"
            },
            [2] = {
                name = "callback",
                type = "function",
                args = {
                    [1] = {
                        name = "context",
                        type = "table"
                    }
                }
            }
        },
        testez = true
    }
    globals.itSKIP = globals.itFOCUS
    globals.itFIXME = globals.itFOCUS
    globals.fit = globals.itFOCUS
    globals.xit = globals.itSKIP
    return globals
end

return testez