type META = {
    string: {
        __concat: (string | number, string | number) -> string,
        __lt: (string, string) -> boolean,
        __le: (string, string) -> boolean,
        __len: (string) -> number
    },
    table: {
        __len: (table) -> number
    },
    number: {
        __concat: (string | number, string | number) -> string,
        __add: (number, number) -> number,
        __sub: (number, number) -> number,
        __mul:
            ((number, number) -> number)
            & ((number, Vector3) -> Vector3)
            & ((number, Vector2) -> Vector2)
            & ((number, Vector3int16) -> Vector3int16)
            & ((number, Vector2int16) -> Vector2int16),
        __div:
            ((number, number) -> number)
            & ((number, Vector3) -> Vector3)
            & ((number, Vector2) -> Vector2)
            & ((number, Vector3int16) -> Vector3int16)
            & ((number, Vector2int16) -> Vector2int16),
        __mod: (number, number) -> number,
        __pow: (number, number) -> number,
        __lt: (number, number) -> boolean,
        __le: (number, number) -> boolean,
        __unm: (number) -> number
    },
    Vector3: {
        __add: (Vector3, Vector3) -> Vector3,
        __sub: (Vector3, Vector3) -> Vector3,
        __div: (Vector3, Vector3 | number) -> Vector3,
        __mul: (Vector3, Vector3 | number) -> Vector3,
        __unm: (Vector3) -> Vector3
    },
    Vector2: {
        __add: (Vector2, Vector2) -> Vector2,
        __sub: (Vector2, Vector2) -> Vector2,
        __div: (Vector2, Vector2 | number) -> Vector2,
        __mul: (Vector2, Vector2 | number) -> Vector2,
        __unm: (Vector2) -> Vector2
    },
    Vector3int16: {
        __add: (Vector3int16, Vector3int16) -> Vector3int16,
        __sub: (Vector3int16, Vector3int16) -> Vector3int16,
        __div: (Vector3int16, Vector3int16 | number) -> Vector3int16,
        __mul: (Vector3int16, Vector3int16 | number) -> Vector3int16,
        __unm: (Vector3int16) -> Vector3int16
    },
    Vector2int16: {
        __add: (Vector2int16, Vector2int16) -> Vector2int16,
        __sub: (Vector2int16, Vector2int16) -> Vector2int16,
        __div: (Vector2int16, Vector2int16 | number) -> Vector2int16,
        __mul: (Vector2int16, Vector2int16 | number) -> Vector2int16,
        __unm: (Vector2int16) -> Vector2int16
    },
    UDim2: {
        __add: (UDim2, UDim2) -> UDim2,
        __sub: (UDim2, UDim2) -> UDim2,
        __unm: (UDim2) -> UDim2
    },
    UDim: {
        __add: (UDim, UDim) -> UDim,
        __sub: (UDim, UDim) -> UDim,
        __unm: (UDim) -> UDim
    },
    CFrame: {
        __mul:
            ((CFrame, CFrame) -> CFrame)
            & ((CFrame, Vector3) -> Vector3),
        __add: (CFrame, Vector3) -> CFrame,
        __sub: (CFrame, Vector3) -> CFrame,
    }
}