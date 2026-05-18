let
    Config = [
        BaseURL = "https://api.reuse.ishibashi.co.jp",
        RelativePath = "api/v1/admin/assessments/",
        ApiKey = ApiKeyParameter,
        StartDate = #date(2025, 11, 1),
        EndDate = Date.From(DateTime.LocalNow()),
        DaysPerRange = 7,
        Limit = 1000
    ],

    ResponseColumnNames = {
        "assessment_type",
        "assessment_slip_number",
        "receipt_number",
        "status",
        "assessment_total_price_including_tax",
        "store_id",
        "name",
        "name_kana",
        "payment_type",
        "bank_name",
        "account_type",
        "is_japan_post_bank",
        "branch_number",
        "account_number",
        "branch_and_account_number_of_japan_post_bank",
        "assessment_confirmation_datetime",
        "assessment_cancellation_datetime"
    },

    RequestBody = Binary.Buffer(Text.ToBinary("{}")),

    CreateDateRanges = (StartDate as date, EndDate as date, DaysPerRange as number) as list =>
        let
            Starts =
                if EndDate <= StartDate then
                    {}
                else
                    List.Generate(
                        () => StartDate,
                        each _ < EndDate,
                        each Date.AddDays(_, DaysPerRange)
                    ),
            Ranges =
                List.Transform(
                    Starts,
                    each
                        [
                            From = _,
                            To = List.Min({Date.AddDays(_, DaysPerRange), EndDate})
                        ]
                )
        in
            Ranges,

    BuildQuery = (PageNumber as number, FromDate as date, ToDate as date) as record =>
        [
            #"limit" = Text.From(Config[Limit]),
            #"page" = Text.From(PageNumber),
            #"filters[0][field]" = "assessment_completed_at_from",
            #"filters[0][operator]" = "gte",
            #"filters[0][value]" = Date.ToText(FromDate, "yyyy-MM-dd"),
            #"filters[1][field]" = "assessment_completed_at_to",
            #"filters[1][operator]" = "lt",
            #"filters[1][value]" = Date.ToText(ToDate, "yyyy-MM-dd")
        ],

    GetJson = (PageNumber as number, FromDate as date, ToDate as date) as record =>
        let
            QueryParams = BuildQuery(PageNumber, FromDate, ToDate),
            Response =
                try
                    Json.Document(
                        Web.Contents(
                            Config[BaseURL],
                            [
                                RelativePath = Config[RelativePath],
                                Query = QueryParams,
                                Headers = [#"X-API-KEY" = Config[ApiKey]],
                                Content = RequestBody
                            ]
                        )
                    )
                otherwise
                    error Text.Format(
                        "API request failed. From=#{0}, To=#{1}, Page=#{2}",
                        {
                            Date.ToText(FromDate, "yyyy-MM-dd"),
                            Date.ToText(ToDate, "yyyy-MM-dd"),
                            Text.From(PageNumber)
                        }
                    ),

            JsonRecord =
                if Value.Is(Response, type record) then
                    Response
                else
                    error "API response is not a JSON record."
        in
            JsonRecord,

    ExtractData = (Json as record) as list =>
        if Record.HasFields(Json, "data")
            and Json[data] <> null
            and Value.Is(Json[data], type list)
        then
            Json[data]
        else
            {},

    ExtractTotal = (Json as record) as number =>
        let
            Meta =
                if Record.HasFields(Json, "meta")
                    and Json[meta] <> null
                    and Value.Is(Json[meta], type record)
                then
                    Json[meta]
                else
                    [],
            Total =
                if Record.HasFields(Meta, "total") then
                    Number.From(Meta[total])
                else
                    0
        in
            Total,

    GetPageData = (PageNumber as number, FromDate as date, ToDate as date) as list =>
        ExtractData(GetJson(PageNumber, FromDate, ToDate)),

    GetRangeData = (FromDate as date, ToDate as date) as list =>
        let
            FirstJson = GetJson(1, FromDate, ToDate),
            Total = ExtractTotal(FirstJson),
            PagesCount =
                if Total <= 0 or Config[Limit] <= 0 then
                    0
                else
                    Number.RoundUp(Total / Config[Limit]),

            FirstData = ExtractData(FirstJson),

            RemainingPageNumbers =
                if PagesCount <= 1 then
                    {}
                else
                    List.Numbers(2, PagesCount - 1),

            RemainingPages =
                List.Transform(
                    RemainingPageNumbers,
                    each GetPageData(_, FromDate, ToDate)
                ),

            PageDataLists = List.Combine({{FirstData}, RemainingPages}),
            Records = List.Combine(PageDataLists)
        in
            Records,

    DateRanges =
        List.Buffer(
            CreateDateRanges(
                Config[StartDate],
                Config[EndDate],
                Config[DaysPerRange]
            )
        ),

    RangeDataLists =
        List.Transform(
            DateRanges,
            each GetRangeData(_[From], _[To])
        ),

    AllRecords = List.Combine(RangeDataLists),

    Result =
        Table.FromRecords(
            AllRecords,
            ResponseColumnNames,
            MissingField.UseNull
        ),

    TypedResult =
        Table.TransformColumnTypes(
            Result,
            {
                {"assessment_type", type text},
                {"assessment_slip_number", type text},
                {"receipt_number", type text},
                {"status", type text},
                {"assessment_total_price_including_tax", Int64.Type},
                {"store_id", Int64.Type},
                {"name", type text},
                {"name_kana", type text},
                {"payment_type", type text},
                {"bank_name", type text},
                {"account_type", type text},
                {"is_japan_post_bank", type logical},
                {"branch_number", type text},
                {"account_number", type text},
                {"branch_and_account_number_of_japan_post_bank", type text},
                {"assessment_confirmation_datetime", type datetime},
                {"assessment_cancellation_datetime", type datetime}
            }
        )
in
    TypedResult
