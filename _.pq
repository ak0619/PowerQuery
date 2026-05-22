// Masters
let
    Definitions = [
        AssessmentTypes = [
            Columns = {
                {"assessment_type_en", type text},
                {"assessment_type_ja", type text}
            },
            Rows = {
                {"BUSINESS_PURCHASES", "業者買取"},
                {"EC_PURCHASES", "EC買取"},
                {"HOME_DELIVERY_PURCHASES", "宅配買取"},
                {"IN_STORE_PURCHASES", "店頭買取"},
                {"ON_SITE_PURCHASES", "出張買取"}
            }
        ],
        AssessmentStatuses = [
            Columns = {
                {"assessment_status_en", type text},
                {"assessment_status_ja", type text}
            },
            Rows = {
                {"ASSESSMENT_COMPLETED", "査定完了"},
                {"AWAITING_PACKING_MATERIAL_SHIPMENT", "梱包材発送待機"},
                {"AWAITING_PICKUP_REQUEST", "集荷依頼待機"},
                {"IN_STORE_APPLICATION_RECEPTION", "店頭申込受付"},
                {"PHONE_APPLICATION_RECEPTION", "電話申込受付"},
                {"PICKUP_ARRANGEMENT_COMPLETED", "集荷手配完了"},
                {"POST_CONFIRMATION_CANCELLATION", "確定後キャンセル"},
                {"PRE_CONFIRMATION_CANCELLATION", "確定前キャンセル"},
                {"PURCHASE_CONFIRMED", "買取確定"},
                {"SIGNATURE_RECEIVED", "サイン受領済"},
                {"UNDER_ASSESSMENT", "査定中"},
                {"WEB_APPLICATION_RECEPTION", "Web申込受付"}
            }
        ],
        PaymentTypes = [
            Columns = {{"payment_type_en", type text}, {"payment_type_ja", type text}},
            Rows = {{"CASH", "現金"}, {"BANK_TRANSFER", "振込"}, {"REGISTERED_MAIL", "書留"}}
        ],
        AccountTypes = [
            Columns = {{"account_type_en", type text}, {"account_type_ja", type text}},
            Rows = {{"ORDINARY", "普通"}, {"PRESENT", "当座"}}
        ],
        Stores = [
            Columns = {{"store_id", type text}, {"store_cd", Int64.Type}},
            Rows = {
                {"2672db15-c643-4bb0-8296-98b9dd055e3e", 3},
                {"46381554-e553-4793-9cab-7c6397fa18db", 4},
                {"6c949a01-aa20-4875-8bbe-508f8e59a3c2", 5},
                {"0a34e430-b01e-44af-810f-409cf6865ffe", 6},
                {"0a88b577-6dcd-4cca-90a7-b1961b662653", 8},
                {"e167ca85-183b-41db-83bf-e06d966b5f6b", 9},
                {"075d24ae-e7c4-48ce-b4a5-05fbd8ea923a", 10},
                {"cd1c42bb-711b-4ffa-a9a7-6688318180b2", 11},
                {"94b225e5-4729-4d79-a96e-fc9b9ed08e6d", 12},
                {"3c5963d8-c744-493b-94ac-d3e174381b1e", 20},
                {"32867f6c-a5db-4563-9990-b55e67b14bce", 84}
            }
        ]
    ],
    BuildTable = (def as record) as table =>
        let
            ColNames = List.Transform(def[Columns], each _{0}),
            TypeMap = List.Transform(def[Columns], each {_{0}, _{1}}),
            Raw = #table(ColNames, def[Rows]),
            Typed = Table.TransformColumnTypes(Raw, TypeMap)
        in
            Typed,
    Result = Record.FromList(
        List.Transform(Record.FieldValues(Definitions), BuildTable),
        Record.FieldNames(Definitions)
    )
in
    Result

// Assessments_Source
let
    Config = [
        BaseURL = "https://api.reuse.ishibashi.co.jp",
        Endpoint = "api/v1/admin/assessments/",
        ApiKey = ApiKeyParameter,
        StartDate = #date(2025, 11, 1),
        EndDate = Date.From(DateTime.LocalNow()),
        DaysPerRange = 7,
        PageSize = 1000
    ],
    PostBody = Binary.Buffer(Text.ToBinary("{}")),
    CreateDateRanges = (start as date, end_ as date, days as number) as list =>
        if end_ <= start then
            {}
        else
            List.Transform(
                List.Generate(() => start, each _ < end_, each Date.AddDays(_, days)),
                each [From = _, To = List.Min({Date.AddDays(_, days), end_})]
            ),
    BuildQuery = (pageNum as number, fromDate as date, toDate as date) as record => [
        limit = Text.From(Config[PageSize]),
        page = Text.From(pageNum),
        #"filters[0][field]" = "assessment_completed_at_from",
        #"filters[0][operator]" = "gte",
        #"filters[0][value]" = Date.ToText(fromDate, "yyyy-MM-dd"),
        #"filters[1][field]" = "assessment_completed_at_to",
        #"filters[1][operator]" = "lt",
        #"filters[1][value]" = Date.ToText(toDate, "yyyy-MM-dd")
    ],
    FetchPage = (pageNum as number, fromDate as date, toDate as date) as record =>
        let
            Raw = try
                Json.Document(
                    Web.Contents(
                        Config[BaseURL],
                        [
                            RelativePath = Config[Endpoint],
                            Query = BuildQuery(pageNum, fromDate, toDate),
                            Headers = [#"X-API-KEY" = Config[ApiKey]],
                            Content = PostBody
                        ]
                    )
                )
        in
            if Raw[HasError] then
                error Text.Format(
                    "API request failed: From=#{0}, To=#{1}, Page=#{2}",
                    {
                        Date.ToText(fromDate, "yyyy-MM-dd"),
                        Date.ToText(toDate, "yyyy-MM-dd"),
                        Text.From(pageNum)
                    }
                )
            else if not Value.Is(Raw[Value], type record) then
                error "API response is not a JSON record."
            else
                Raw[Value],
    ExtractData = (json as record) as list =>
        let
            value = try json[data] otherwise null
        in
            if value <> null and Value.Is(value, type list) then value else {},
    ExtractTotal = (json as record) as number =>
        try Number.From(json[meta][total]) otherwise 0,
    FetchRange = (fromDate as date, toDate as date) as list =>
        let
            FirstResponse = FetchPage(1, fromDate, toDate),
            Total = ExtractTotal(FirstResponse),
            PageCount =
                if Total <= 0 then
                    0
                else
                    Number.RoundUp(Total / Config[PageSize]),
            AllPages = {ExtractData(FirstResponse)}
                & (
                    if PageCount <= 1 then
                        {}
                    else
                        List.Transform(
                            List.Numbers(2, PageCount - 1),
                            each ExtractData(FetchPage(_, fromDate, toDate))
                        )
                )
        in
            List.Combine(AllPages),
    DateRanges = List.Buffer(
        CreateDateRanges(Config[StartDate], Config[EndDate], Config[DaysPerRange])
    ),
    AllRecords = List.Combine(
        List.Transform(DateRanges, each FetchRange(_[From], _[To]))
    ),
    RawTable = Table.FromRecords(AllRecords, null, MissingField.UseNull)
in
    RawTable

// Assessments_Transform
let
    Source = Assessments_Source,
    ToLookup = (table as table) as record =>
        let
            columns = Table.ColumnNames(table),
            keys = Table.Column(table, columns{0}),
            values = Table.Column(table, columns{1})
        in
            Record.FromList(values, keys),
    AssessmentTypeMap = ToLookup(Masters[AssessmentTypes]),
    AssessmentStatusMap = ToLookup(Masters[AssessmentStatuses]),
    PaymentTypeMap = ToLookup(Masters[PaymentTypes]),
    AccountTypeMap = ToLookup(Masters[AccountTypes]),
    StoreMap = ToLookup(Masters[Stores]),
    Schema = {
        {"assessment_type", "査定形態", type text, AssessmentTypeMap},
        {"assessment_slip_number", "査定伝票番号", Int64.Type, null},
        {"receipt_number", "領収書番号", Int64.Type, null},
        {"status", "査定ステータス", type text, AssessmentStatusMap},
        {"assessment_total_price_including_tax", "査定金額", Int64.Type, null},
        {"store_id", "店舗CD", Int64.Type, StoreMap},
        {"name", "申込者氏名", type text, null},
        {"name_kana", "申込者カナ", type text, null},
        {"payment_type", "支払種別", type text, PaymentTypeMap},
        {"bank_name", "銀行支店", type text, null},
        {"account_type", "口座種別", type text, AccountTypeMap},
        {"is_japan_post_bank", "ゆうちょ銀行区分", type logical, null},
        {"branch_number", "支店番号", type text, null},
        {"account_number", "口座番号", type text, null},
        {"branch_and_account_number_of_japan_post_bank", "記号番号", type text, null},
        {"assessment_confirmation_datetime", "買取確定日時", type datetime, null},
        {"assessment_cancellation_datetime", "買取キャンセル日時", type datetime, null}
    },
    SourceColumns = List.Transform(Schema, each _{0}),
    Selected = Table.SelectColumns(Source, SourceColumns, MissingField.UseNull),
    StatusFilter = {"PURCHASE_CONFIRMED", "POST_CONFIRMATION_CANCELLATION"},
    Filtered = Table.SelectRows(Selected, each List.Contains(StatusFilter, [status])),
    Transformations = List.Transform(
        List.Select(Schema, each _{3} <> null),
        (row) => {
            row{0},
            (value) =>
                if value = null then
                    null
                else
                    Record.FieldOrDefault(row{3}, value, value)
        }
    ),
    Translated = Table.TransformColumns(
        Filtered,
        Transformations,
        null,
        MissingField.UseNull
    ),
    RenameMap = List.Transform(Schema, each {_{0}, _{1}}),
    Renamed = Table.RenameColumns(Translated, RenameMap),
    TypeMap = List.Transform(Schema, each {_{1}, _{2}}),
    Typed = Table.TransformColumnTypes(Renamed, TypeMap)
in
    Typed

// Assessments
let
    Source = Assessments_Transform
in
    Source
