// Masters
let
    TableDefinitions = [
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
    BuildTableFromDefinition = (definition as record) as table =>
        let
            columnNames = List.Transform(definition[Columns], each _{0}),
            columnTypeMap = List.Transform(definition[Columns], each {_{0}, _{1}}),
            untypedTable = #table(columnNames, definition[Rows]),
            typedTable = Table.TransformColumnTypes(untypedTable, columnTypeMap)
        in
            typedTable,
    MasterTables = Record.FromList(
        List.Transform(Record.FieldValues(TableDefinitions), BuildTableFromDefinition),
        Record.FieldNames(TableDefinitions)
    )
in
    MasterTables

// Assessments_Source
let
    Configuration = [
        BaseUrl = "https://api.reuse.ishibashi.co.jp",
        Endpoint = "api/v1/admin/assessments/",
        ApiKey = ApiKeyParameter,
        // FromDate = Date.AddMonths(Date.From(DateTime.LocalNow()), - 1),
        FromDate = #date(2025, 11, 1),
        ToDate = Date.AddDays(Date.From(DateTime.LocalNow()), 1),
        DaysPerRange = 7,
        PageSize = 1000,
        RequestIntervalSeconds = 1
    ],
    PostRequestBody = Binary.Buffer(Text.ToBinary("{}")),
    CreateDateRanges = (startDate as date, endDate as date, intervalDays as number) as list =>
        if endDate <= startDate then
            {}
        else
            List.Transform(
                List.Generate(
                    () => startDate,
                    each _ < endDate,
                    each Date.AddDays(_, intervalDays)
                ),
                each [
                    FromDate = _,
                    ToDate = List.Min({Date.AddDays(_, intervalDays), endDate})
                ]
            ),
    BuildQueryParameters = (pageNumber as number, fromDate as date, toDate as date) as record => [
        limit = Text.From(Configuration[PageSize]),
        page = Text.From(pageNumber),
        #"filters[0][field]" = "assessment_completed_at_from",
        #"filters[0][operator]" = "eq",
        #"filters[0][value]" = Date.ToText(fromDate, "yyyy-MM-dd"),
        #"filters[1][field]" = "assessment_completed_at_to",
        #"filters[1][operator]" = "eq",
        #"filters[1][value]" = Date.ToText(toDate, "yyyy-MM-dd")
    ],
    FetchPage = (pageNumber as number, fromDate as date, toDate as date) as record =>
        let
            apiResponse = try
                Json.Document(
                    Web.Contents(
                        Configuration[BaseUrl],
                        [
                            RelativePath = Configuration[Endpoint],
                            Query = BuildQueryParameters(pageNumber, fromDate, toDate),
                            Headers = [#"X-API-KEY" = Configuration[ApiKey]],
                            Content = PostRequestBody
                        ]
                    )
                )
        in
            if apiResponse[HasError] then
                error Text.Format(
                    "API request failed: From=#{0}, To=#{1}, Page=#{2}",
                    {
                        Date.ToText(fromDate, "yyyy-MM-dd"),
                        Date.ToText(toDate, "yyyy-MM-dd"),
                        Text.From(pageNumber)
                    }
                )
            else if not Value.Is(apiResponse[Value], type record) then
                error "API response is not a JSON record."
            else
                apiResponse[Value],
    FetchPageWithDelay = (pageNumber as number, fromDate as date, toDate as date) as record =>
        Function.InvokeAfter(
            () => FetchPage(pageNumber, fromDate, toDate),
            #duration(0, 0, 0, Configuration[RequestIntervalSeconds])
        ),
    ExtractDataList = (jsonRecord as record) as list =>
        let
            dataValue = try jsonRecord[data] otherwise null
        in
            if dataValue <> null and Value.Is(dataValue, type list) then
                dataValue
            else
                {},
    ExtractTotalCount = (jsonRecord as record) as number =>
        try Number.From(jsonRecord[meta][total]) otherwise 0,
    FetchDateRange = (fromDate as date, toDate as date) as list =>
        let
            firstPageResponse = FetchPageWithDelay(1, fromDate, toDate),
            totalCount = ExtractTotalCount(firstPageResponse),
            pageCount =
                if totalCount <= 0 then
                    0
                else
                    Number.RoundUp(totalCount / Configuration[PageSize]),
            combinedPageData = {ExtractDataList(firstPageResponse)}
                & (
                    if pageCount <= 1 then
                        {}
                    else
                        List.Transform(
                            List.Numbers(2, pageCount - 1),
                            each ExtractDataList(
                                FetchPageWithDelay(_, fromDate, toDate)
                            )
                        )
                )
        in
            List.Combine(combinedPageData),
    DateRanges = List.Buffer(
        CreateDateRanges(
            Configuration[FromDate],
            Configuration[ToDate],
            Configuration[DaysPerRange]
        )
    ),
    AllRecords = List.Combine(
        List.Transform(DateRanges, each FetchDateRange(_[FromDate], _[ToDate]))
    ),
    RawTable = Table.FromRecords(AllRecords, null, MissingField.UseNull)
in
    RawTable

// Assessments_Transform
let
    Source = Assessments_Source,
    BuildLookupRecord = (lookupTable as table) as record =>
        let
            columnNames = Table.ColumnNames(lookupTable),
            keyColumn = Table.Column(lookupTable, columnNames{0}),
            valueColumn = Table.Column(lookupTable, columnNames{1})
        in
            Record.FromList(valueColumn, keyColumn),
    StripSpacesAndControl = (inputValue as nullable text) as nullable text =>
        if inputValue = null then
            null
        else
            Text.Remove(Text.Clean(inputValue), {" ", "　", Character.FromNumber(160)}),
    BankSuffixes = {"農業協同組合", "漁業協同組合", "信用金庫", "信用組合", "労働金庫", "信託銀行", "銀行"},
    BranchSuffixes = {"本店営業部", "出張所", "営業部", "支店", "支所", "本店"},
    KanjiDigits = {"〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"},
    FindEarliestSuffix = (inputText as text, suffixes as list) as nullable record =>
        let
            matchedSuffixes = List.Select(
                List.Transform(
                    suffixes,
                    (suffix) => [
                        Position = Text.PositionOf(inputText, suffix),
                        Length = Text.Length(suffix)
                    ]
                ),
                each [Position] <> - 1
            ),
            earliestMatch = List.Accumulate(
                matchedSuffixes,
                null,
                (currentBest, candidate) =>
                    if currentBest = null then
                        candidate
                    else if candidate[Position] < currentBest[Position] then
                        candidate
                    else if candidate[Position]
                        = currentBest[Position]
                        and candidate[Length] > currentBest[Length]
                    then
                        candidate
                    else
                        currentBest
            )
        in
            earliestMatch,
    DeriveJapanPostBranchName = (japanPostNumber as nullable text) as nullable text =>
        if japanPostNumber = null or japanPostNumber = "" then
            null
        else
            let
                digitsOnly = Text.Select(japanPostNumber, {"0" .. "9"}),
                symbolDigits =
                    if Text.Length(digitsOnly) >= 5 then
                        Text.Start(digitsOnly, 5)
                    else
                        null,
                branchCode =
                    if symbolDigits = null then
                        null
                    else
                        let
                            firstDigit = Text.Start(symbolDigits, 1),
                            middleDigits = Text.Range(symbolDigits, 1, 2),
                            suffixDigit = if firstDigit = "0" then "9" else "8"
                        in
                            middleDigits & suffixDigit,
                branchName =
                    if branchCode = null then
                        null
                    else
                        Text.Combine(
                            List.Transform(
                                Text.ToList(branchCode),
                                (digitCharacter) =>
                                    KanjiDigits{Number.FromText(digitCharacter)}
                            )
                        )
            in
                branchName,
    ExtractBankAndBranch = (
        bankBranchText as nullable text,
        isJapanPostBank as nullable logical,
        japanPostNumber as nullable text
    ) as record =>
        let
            baseResult =
                if bankBranchText = null or bankBranchText = "" then
                    [銀行名 = null, 支店名 = null]
                else
                    let
                        bankSuffixHit = FindEarliestSuffix(bankBranchText, BankSuffixes)
                    in
                        if bankSuffixHit = null then
                            [銀行名 = null, 支店名 = null]
                        else
                            let
                                bankNameEnd = bankSuffixHit[Position]
                                    + bankSuffixHit[Length],
                                bankName = Text.Start(bankBranchText, bankNameEnd),
                                remainder = Text.Middle(bankBranchText, bankNameEnd),
                                branchSuffixHit = FindEarliestSuffix(
                                    remainder,
                                    BranchSuffixes
                                ),
                                branchName =
                                    if branchSuffixHit = null then
                                        if remainder = "" then null else remainder
                                    else
                                        Text.Start(
                                            remainder,
                                            branchSuffixHit[Position]
                                                + branchSuffixHit[Length]
                                        )
                            in
                                [銀行名 = bankName, 支店名 = branchName],
            needsJapanPostFallback = isJapanPostBank
                = true
                and (
                    baseResult[銀行名]
                        = null
                        or not Text.Contains(baseResult[銀行名], "ゆうちょ銀行")
                ),
            afterJapanPostFix =
                if needsJapanPostFallback then
                    [銀行名 = "ゆうちょ銀行", 支店名 = baseResult[支店名]]
                else
                    baseResult,
            isJapanPost = afterJapanPostFix[銀行名]
                <> null
                and Text.Contains(afterJapanPostFix[銀行名], "ゆうちょ銀行"),
            derivedBranchName =
                if isJapanPost and afterJapanPostFix[支店名] = null then
                    DeriveJapanPostBranchName(japanPostNumber)
                else
                    afterJapanPostFix[支店名],
            finalBranchName =
                if isJapanPost
                    and derivedBranchName <> null
                    and Text.EndsWith(derivedBranchName, "支店")
                then
                    Text.Start(derivedBranchName, Text.Length(derivedBranchName) - 2)
                else
                    derivedBranchName
        in
            [銀行名 = afterJapanPostFix[銀行名], 支店名 = finalBranchName],
    AssessmentTypeLookup = BuildLookupRecord(Masters[AssessmentTypes]),
    AssessmentStatusLookup = BuildLookupRecord(Masters[AssessmentStatuses]),
    PaymentTypeLookup = BuildLookupRecord(Masters[PaymentTypes]),
    AccountTypeLookup = BuildLookupRecord(Masters[AccountTypes]),
    StoreLookup = BuildLookupRecord(Masters[Stores]),
    ColumnSchema = {
        [
            SourceColumn = "assessment_type",
            DestinationColumn = "査定形態",
            ColumnType = type text,
            Lookup = AssessmentTypeLookup,
            Normalizer = null
        ],
        [
            SourceColumn = "assessment_slip_number",
            DestinationColumn = "査定伝票番号",
            ColumnType = Int64.Type,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "receipt_number",
            DestinationColumn = "領収書番号",
            ColumnType = Int64.Type,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "status",
            DestinationColumn = "査定ステータス",
            ColumnType = type text,
            Lookup = AssessmentStatusLookup,
            Normalizer = null
        ],
        [
            SourceColumn = "assessment_total_price_including_tax",
            DestinationColumn = "査定金額",
            ColumnType = Int64.Type,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "store_id",
            DestinationColumn = "店舗CD",
            ColumnType = Int64.Type,
            Lookup = StoreLookup,
            Normalizer = null
        ],
        [
            SourceColumn = "name",
            DestinationColumn = "申込者氏名",
            ColumnType = type text,
            Lookup = null,
            Normalizer = StripSpacesAndControl
        ],
        [
            SourceColumn = "name_kana",
            DestinationColumn = "申込者カナ",
            ColumnType = type text,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "payment_type",
            DestinationColumn = "支払種別",
            ColumnType = type text,
            Lookup = PaymentTypeLookup,
            Normalizer = null
        ],
        [
            SourceColumn = "bank_name",
            DestinationColumn = "金融機関",
            ColumnType = type text,
            Lookup = null,
            Normalizer = StripSpacesAndControl
        ],
        [
            SourceColumn = "account_type",
            DestinationColumn = "口座種別",
            ColumnType = type text,
            Lookup = AccountTypeLookup,
            Normalizer = null
        ],
        [
            SourceColumn = "is_japan_post_bank",
            DestinationColumn = "ゆうちょ銀行区分",
            ColumnType = type logical,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "branch_number",
            DestinationColumn = "支店番号",
            ColumnType = type text,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "account_number",
            DestinationColumn = "口座番号",
            ColumnType = type text,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "branch_and_account_number_of_japan_post_bank",
            DestinationColumn = "記号番号",
            ColumnType = type text,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "assessment_confirmation_datetime",
            DestinationColumn = "買取確定日時",
            ColumnType = type datetime,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "assessment_cancellation_datetime",
            DestinationColumn = "買取キャンセル日時",
            ColumnType = type datetime,
            Lookup = null,
            Normalizer = null
        ]
    },
    SourceColumnList = List.Transform(ColumnSchema, each [SourceColumn]),
    SelectedColumnsTable = Table.SelectColumns(
        Source,
        SourceColumnList,
        MissingField.UseNull
    ),
    StatusFilter = {"PURCHASE_CONFIRMED", "POST_CONFIRMATION_CANCELLATION"},
    FilteredTable = Table.SelectRows(
        SelectedColumnsTable,
        each List.Contains(StatusFilter, [status])
    ),
    ValueTransformations = List.Transform(
        List.Select(ColumnSchema, each [Lookup] <> null or [Normalizer] <> null),
        (schemaRow) => {
            schemaRow[SourceColumn],
            (cellValue) =>
                let
                    mappedValue =
                        if schemaRow[Lookup] <> null and cellValue <> null then
                            Record.FieldOrDefault(
                                schemaRow[Lookup],
                                cellValue,
                                cellValue
                            )
                        else
                            cellValue,
                    normalizedValue =
                        if schemaRow[Normalizer] <> null then
                            schemaRow[Normalizer](mappedValue)
                        else
                            mappedValue
                in
                    normalizedValue
        }
    ),
    TransformedTable = Table.TransformColumns(
        FilteredTable,
        ValueTransformations,
        null,
        MissingField.UseNull
    ),
    RenamedTable = Table.RenameColumns(
        TransformedTable,
        List.Transform(ColumnSchema, each {[SourceColumn], [DestinationColumn]})
    ),
    TypedTable = Table.TransformColumnTypes(
        RenamedTable,
        List.Transform(ColumnSchema, each {[DestinationColumn], [ColumnType]})
    ),
    TableWithBankBranchSplit = Table.AddColumn(
        TypedTable,
        "_BankBranchSplit",
        each ExtractBankAndBranch([金融機関], [ゆうちょ銀行区分], [記号番号]),
        type record
    ),
    ExpandedTable = Table.ExpandRecordColumn(
        TableWithBankBranchSplit,
        "_BankBranchSplit",
        {"銀行名", "支店名"},
        {"銀行名", "支店名"}
    )
in
    ExpandedTable

// Assessments
let
    Source = Assessments_Transform
in
    Source
