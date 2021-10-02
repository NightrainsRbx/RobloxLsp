export type Fusion.State<T> = {
  get: (self: Fusion.State<T>, asDependency: boolean?) -> T,
  set: (self: Fusion.State<T>, newValue: any, force: boolean?) -> ()
}

export type Fusion.Computed<T> = {
  get: (self: Fusion.Computed<T>, asDependency: boolean?) -> T,
  update: (self: Fusion.Computed<T>) -> boolean
}

export type Fusion.Compat = {
  update: (self: Fusion.Compat) -> boolean,
  onChange: (self: Fusion.Compat, callback: () -> ()) -> ()
}

export type Fusion.Symbol = {
	type: string,
	name: string,
	key: string?
}

export type Fusion.Error = {
	raw: string,
	message: string,
	trace: string
}

type StateOrValue<T> = Fusion.State<T> | T

type Animatable =
	number |
	CFrame |
	Color3 |
	ColorSequenceKeypoint |
	DateTime |
	NumberRange |
	NumberSequenceKeypoint |
	PhysicalProperties |
	Ray |
	Rect |
	Region3 |
	Region3int16 |
	UDim |
	UDim2 |
	Vector2 |
	Vector2int16 |
	Vector3 |
	Vector3int16

export type Fusion.Tween<T> = {
	get: (self: Fusion.Tween<T>, asDependency: boolean?) -> Fusion.State<T>,
	update: (self: Fusion.Tween<T>) -> (),
	-- Uncomment when ENABLE_PARAM_SETTERS is enabled
	-- setTweenInfo: (Tween<T>, newTweenInfo: TweenInfo) -> ()
}

export type Fusion.Spring<T> = {
	get: (self: Fusion.Spring<T>, asDependency: boolean?) -> any,
	update: (self: Fusion.Spring<T>) -> (),
	-- Uncomment when ENABLE_PARAM_SETTERS is enabled
	-- setDamping: (Spring<T>, damping: number) -> (),
	-- setSpeed: (Spring<T>, speed: number) -> (),
	-- setPosition: (Spring<T>, newValue: Animatable) -> (),
	-- setVelocity: (Spring<T>, newValue: Animatable) -> (),
	-- addVelocity: (Spring<T>, deltaValue: Animatable) -> ()
}

export type Fusion = {
  New: (className: string) -> ((propertyTable: {[string | Fusion.Symbol]: any}) -> Instance | nil),
  Children: Fusion.Symbol,
  OnEvent: (eventName: string) -> Fusion.Symbol,
  OnChange: (propertyName: string) -> Fusion.Symbol,

  State: (initialValue: any) -> Fusion.State<any>,
  Computed: (callback: () -> any) -> Fusion.Computed<any>,
  ComputedPairs: (inputTable: StateOrValue<{[any]: any}>, processor: (any) -> any, destructor: (any) -> ()?) -> Fusion.Computed<any>,
  Compat: (watchedState: Fusion.State<any>) -> Fusion.Compat,

  Tween: (goalState: Fusion.State<Animatable>, tweenInfo: TweenInfo?) -> Fusion.Tween<any>,
  Spring: (goalState: Fusion.State<Animatable>, speed: number?, damping: number?) -> Fusion.Spring<any>
}