export type RoactRodux = Readonly<{
    StoreProvider: Roact.Component,
    connect: (
        mapStateToProps: ((storeState: any?, props: table?) -> table)?,
        mapDispatchToProps: ((dispatchFn: function) -> table)?
    ) -> (componentToWrap: Roact.Component) -> Roact.Component
}>