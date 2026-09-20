@{
    Modules = @(
        # Pester is the coverage collector only; the tests use TestKit.psm1.
        @{
            Name           = 'Pester'
            MinimumVersion = '6.0.0'
            Uri            = 'https://pester.dev/docs/introduction/installation'
        }
    )
}
