// Masters
let
    TableDefinitions = [
        AssessmentTypes = [
            Columns = {{"Code", type text}, {"Label", type text}},
            Rows = {
                {"BUSINESS_PURCHASES", "業者買取"},
                {"EC_PURCHASES", "EC買取"},
                {"HOME_DELIVERY_PURCHASES", "宅配買取"},
                {"IN_STORE_PURCHASES", "店頭買取"},
                {"ON_SITE_PURCHASES", "出張買取"}
            }
        ],
        AssessmentStatuses = [
            Columns = {{"Code", type text}, {"Label", type text}},
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
            Columns = {{"Code", type text}, {"Label", type text}},
            Rows = {{"CASH", "現金"}, {"BANK_TRANSFER", "振込"}, {"REGISTERED_MAIL", "書留"}}
        ],
        AccountTypes = [
            Columns = {{"Code", type text}, {"Label", type text}},
            Rows = {{"ORDINARY", "普通"}, {"PRESENT", "当座"}}
        ],
        Stores = [
            Columns = {{"StoreId", type text}, {"StoreCode", Int64.Type}},
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

// BankAccountExtraction
let
    BankSuffixes = {"農業協同組合", "漁業協同組合", "信用金庫", "信用組合", "労働金庫", "信託銀行", "銀行"},
    BranchSuffixes = {"本店営業部", "出張所", "営業部", "支店", "支所", "本店"},
    KanjiDigits = {"〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"},
    FullWidthDigits = {"０", "１", "２", "３", "４", "５", "６", "７", "８", "９"},
    JapanPostBankName = "ゆうちょ銀行",
    ConvertHalfWidthToFullWidth = (inputValue as nullable text) as nullable text =>
        if inputValue = null or inputValue = "" then
            inputValue
        else
            Text.Combine(
                List.Transform(
                    Text.ToList(inputValue),
                    (character) =>
                        let
                            code = Character.ToNumber(character)
                        in
                            if code = 32 then
                                Character.FromNumber(12288)
                            else if code >= 33 and code <= 126 then
                                Character.FromNumber(code + 65248)
                            else
                                character
                )
            ),
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
    ConvertDigitsToKanji = (numericText as nullable text) as nullable text =>
        if numericText = null or numericText = "" then
            null
        else
            Text.Combine(
                List.Transform(
                    Text.ToList(numericText),
                    (digitCharacter) => KanjiDigits{Number.FromText(digitCharacter)}
                )
            ),
    NormalizeToAsciiDigits = (inputText as nullable text) as nullable text =>
        if inputText = null or inputText = "" then
            null
        else
            let
                kanjiNormalized = List.Accumulate(
                    List.Positions(KanjiDigits),
                    inputText,
                    (state, index) =>
                        Text.Replace(state, KanjiDigits{index}, Text.From(index))
                ),
                fullWidthNormalized = List.Accumulate(
                    List.Positions(FullWidthDigits),
                    kanjiNormalized,
                    (state, index) =>
                        Text.Replace(state, FullWidthDigits{index}, Text.From(index))
                )
            in
                fullWidthNormalized,
    CoalesceFirstNonNull = (candidates as list) as nullable text =>
        List.First(List.Select(candidates, each _ <> null), null),
    ExtractJapanPostAccountFields = (japanPostNumber as nullable text) as record =>
        if japanPostNumber = null or japanPostNumber = "" then
            [支店番号 = null, 口座番号 = null]
        else
            let
                digitsOnly = Text.Select(japanPostNumber, {"0" .. "9"}),
                symbolDigits =
                    if Text.Length(digitsOnly) >= 5 then
                        Text.Start(digitsOnly, 5)
                    else
                        null,
                numberDigits =
                    if symbolDigits <> null and Text.Length(digitsOnly) > 5 then
                        Text.Middle(digitsOnly, 5)
                    else
                        null,
                firstDigit =
                    if symbolDigits <> null then
                        Text.Start(symbolDigits, 1)
                    else
                        null,
                isOrdinary = firstDigit = "1",
                isCurrent = firstDigit = "0",
                isValidPrefix = isOrdinary or isCurrent,
                branchNumber =
                    if symbolDigits = null or not isValidPrefix then
                        null
                    else
                        Text.Range(symbolDigits, 1, 2)
                            & (if isCurrent then "9" else "8"),
                accountNumber =
                    if numberDigits = null or numberDigits = "" or not isValidPrefix then
                        null
                    else if isOrdinary and Text.End(numberDigits, 1) = "1" then
                        Text.Start(numberDigits, Text.Length(numberDigits) - 1)
                    else
                        numberDigits
            in
                [支店番号 = branchNumber, 口座番号 = accountNumber],
    ExtractBranchNumberFromText = (bankBranchText as nullable text) as nullable text =>
        if bankBranchText = null or bankBranchText = "" then
            null
        else
            let
                afterBank =
                    if Text.Contains(bankBranchText, JapanPostBankName) then
                        Text.Middle(
                            bankBranchText,
                            Text.PositionOf(bankBranchText, JapanPostBankName)
                                + Text.Length(JapanPostBankName)
                        )
                    else
                        bankBranchText,
                branchSuffixHit = FindEarliestSuffix(afterBank, BranchSuffixes),
                beforeBranchSuffix =
                    if branchSuffixHit = null then
                        afterBank
                    else
                        Text.Start(afterBank, branchSuffixHit[Position]),
                asciiNormalized = NormalizeToAsciiDigits(beforeBranchSuffix),
                digitsOnly =
                    if asciiNormalized = null then
                        ""
                    else
                        Text.Select(asciiNormalized, {"0" .. "9"}),
                lastThree =
                    if Text.Length(digitsOnly) >= 3 then
                        Text.End(digitsOnly, 3)
                    else
                        null
            in
                lastThree,
    ValidateBranchNumber = (branchNumber as nullable text, accountType as nullable text) as nullable text =>
        if branchNumber = null or branchNumber = "" then
            null
        else
            let
                digitsOnly = Text.Select(Text.From(branchNumber), {"0" .. "9"}),
                expectedSuffix =
                    if accountType <> null and Text.Contains(accountType, "普通") then
                        "8"
                    else if accountType <> null and Text.Contains(accountType, "当座") then
                        "9"
                    else
                        null,
                isThreeDigits = Text.Length(digitsOnly) = 3,
                hasExpectedSuffix = expectedSuffix
                    <> null
                    and Text.End(digitsOnly, 1) = expectedSuffix
            in
                if isThreeDigits and hasExpectedSuffix then digitsOnly else null,
    Extract = (
        bankBranchText as nullable text,
        isJapanPostBank as nullable logical,
        japanPostNumber as nullable text,
        accountType as nullable text,
        originalBranchNumber as nullable text,
        originalAccountNumber as nullable text
    ) as record =>
        let
            isJapanPostByName = bankBranchText
                <> null
                and Text.Contains(bankBranchText, JapanPostBankName),
            baseResult =
                if bankBranchText = null or bankBranchText = "" then
                    [金融機関名 = null, 支店名 = null]
                else if isJapanPostByName then
                    let
                        japanPostPosition = Text.PositionOf(
                            bankBranchText,
                            JapanPostBankName
                        ),
                        bankNameEnd = japanPostPosition + Text.Length(JapanPostBankName),
                        remainder = Text.Middle(bankBranchText, bankNameEnd),
                        branchSuffixHit = FindEarliestSuffix(remainder, BranchSuffixes),
                        branchName =
                            if branchSuffixHit = null then
                                if remainder = "" then null else remainder
                            else
                                Text.Start(
                                    remainder,
                                    branchSuffixHit[Position] + branchSuffixHit[Length]
                                )
                    in
                        [金融機関名 = JapanPostBankName, 支店名 = branchName]
                else
                    let
                        bankSuffixHit = FindEarliestSuffix(bankBranchText, BankSuffixes)
                    in
                        if bankSuffixHit = null then
                            [金融機関名 = null, 支店名 = null]
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
                                [金融機関名 = bankName, 支店名 = branchName],
            needsJapanPostFallback = isJapanPostBank
                = true
                and (
                    baseResult[金融機関名]
                        = null
                        or not Text.Contains(baseResult[金融機関名], JapanPostBankName)
                ),
            afterJapanPostFix =
                if needsJapanPostFallback then
                    [金融機関名 = JapanPostBankName, 支店名 = baseResult[支店名]]
                else
                    baseResult,
            isJapanPost = afterJapanPostFix[金融機関名]
                <> null
                and Text.Contains(afterJapanPostFix[金融機関名], JapanPostBankName),
            japanPostExtract =
                if isJapanPost then
                    ExtractJapanPostAccountFields(japanPostNumber)
                else
                    [支店番号 = null, 口座番号 = null],
            branchCandidates =
                if isJapanPost then
                    {
                        ValidateBranchNumber(japanPostExtract[支店番号], accountType),
                        ValidateBranchNumber(
                            ExtractBranchNumberFromText(bankBranchText),
                            accountType
                        ),
                        ValidateBranchNumber(originalBranchNumber, accountType)
                    }
                else
                    {},
            finalBranchNumber =
                if isJapanPost then
                    CoalesceFirstNonNull(branchCandidates)
                else
                    originalBranchNumber,
            finalBranchName =
                if isJapanPost then
                    if finalBranchNumber <> null then
                        ConvertDigitsToKanji(finalBranchNumber)
                    else
                        null
                else
                    afterJapanPostFix[支店名],
            finalAccountNumber =
                if isJapanPost and japanPostExtract[口座番号] <> null then
                    japanPostExtract[口座番号]
                else
                    originalAccountNumber
        in
            [
                金融機関名 = ConvertHalfWidthToFullWidth(afterJapanPostFix[金融機関名]),
                支店名 = ConvertHalfWidthToFullWidth(finalBranchName),
                支店番号 = finalBranchNumber,
                口座番号 = finalAccountNumber
            ]
in
    [Extract = Extract]

// TextNormalizers
let
    SmallToLargeKana = {
        {"ァ", "ア"},
        {"ィ", "イ"},
        {"ゥ", "ウ"},
        {"ェ", "エ"},
        {"ォ", "オ"},
        {"ャ", "ヤ"},
        {"ュ", "ユ"},
        {"ョ", "ヨ"},
        {"ッ", "ツ"}
    },
    LegalEntityAbbreviations = {
        {"イリヨウホウジンシヤダン", "イ"},
        {"イリヨウホウジンザイダン", "イ"},
        {"シヤカイイリヨウホウジン", "イ"},
        {"イリヨウホウジン", "イ"},
        {"イツパンザイダンホウジン", "ザイ"},
        {"コウエキザイダンホウジン", "ザイ"},
        {"ザイダンホウジン", "ザイ"},
        {"イツパンシヤダンホウジン", "シヤ"},
        {"コウエキシヤダンホウジン", "シヤ"},
        {"シヤダンホウジン", "シヤ"},
        {"シユウキヨウホウジン", "シユウ"},
        {"ガツコウホウジン", "ガク"},
        {"シヤカイフクシホウジン", "フク"},
        {"コウセイホゴホウジン", "ホゴ"},
        {"トクテイヒエイリカツドウホウジン", "トクヒ"},
        {"チホウドクリツギヨウセイホウジン", "チドク"},
        {"ドクリツギヨウセイホウジン", "ドク"},
        {"チユウキモクヒヨウカンリホウジン", "モク"},
        {"コクリツケンキユウカイハツホウジン", "ケン"},
        {"ギヨウセイシツコウホウジン", "シツ"},
        {"ベンゴシホウジン", "ベン"},
        {"ユウゲンセキニンチユウカンホウジン", "チユウ"},
        {"ムゲンセキニンチユウカンホウジン", "チユウ"},
        {"ギヨウセイシヨシホウジン", "ギヨ"},
        {"シホウシヨシホウジン", "シホウ"},
        {"ゼイリシホウジン", "ゼイ"},
        {"コクリツダイガクホウジン", "ダイ"},
        {"コウリツダイガクホウジン", "ダイ"},
        {"ノウジクミアイホウジン", "ノウ"},
        {"カンリクミアイホウジン", "カンリ"},
        {"シヤカイホケンロウムシホウジン", "ロウム"},
        {"カブシキガイシヤ", "カ"},
        {"ユウゲンガイシヤ", "ユ"},
        {"ゴウメイガイシヤ", "メ"},
        {"ゴウシガイシヤ", "シ"},
        {"ゴウドウガイシヤ", "ド"},
        {"ソウゴガイシヤ", "ソ"}
    },
    StripSpacesAndControl = (inputValue as nullable text) as nullable text =>
        if inputValue = null then
            null
        else
            Text.Remove(Text.Clean(inputValue), {" ", "　", Character.FromNumber(160)}),
    ConvertLegalEntityToAbbreviation = (inputValue as nullable text) as nullable text =>
        if inputValue = null or inputValue = "" then
            inputValue
        else
            let
                normalized = List.Accumulate(
                    SmallToLargeKana,
                    inputValue,
                    (state, pair) => Text.Replace(state, pair{0}, pair{1})
                ),
                matchedPair = List.First(
                    List.Select(
                        LegalEntityAbbreviations,
                        (pair) => Text.Contains(normalized, pair{0})
                    ),
                    null
                )
            in
                if matchedPair = null then
                    inputValue
                else
                    let
                        term = matchedPair{0},
                        abbreviation = matchedPair{1},
                        position = Text.PositionOf(normalized, term),
                        termLength = Text.Length(term),
                        before = Text.Start(inputValue, position),
                        after = Text.Middle(inputValue, position + termLength),
                        replaced =
                            if position = 0 and after <> "" then
                                abbreviation & "）" & after
                            else if position = 0 and after = "" then
                                "（" & abbreviation
                            else if after = "" then
                                before & "（" & abbreviation
                            else
                                before & "（" & abbreviation & "）" & after
                    in
                        replaced
in
    [
        StripSpacesAndControl = StripSpacesAndControl,
        ConvertLegalEntityToAbbreviation = ConvertLegalEntityToAbbreviation
    ]

// AssessmentsSource
let
    Configuration = [
        BaseUrl = "https://api.reuse.ishibashi.co.jp",
        Endpoint = "api/v1/admin/assessments/",
        ApiKey = ApiKeyParameter,
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

// AssessmentsTransform
let
    Source = AssessmentsSource,
    BuildLookupRecord = (lookupTable as table) as record =>
        let
            columnNames = Table.ColumnNames(lookupTable),
            keyColumn = Table.Column(lookupTable, columnNames{0}),
            valueColumn = Table.Column(lookupTable, columnNames{1})
        in
            Record.FromList(valueColumn, keyColumn),
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
            Normalizer = TextNormalizers[StripSpacesAndControl]
        ],
        [
            SourceColumn = "name_kana",
            DestinationColumn = "申込者カナ",
            ColumnType = type text,
            Lookup = null,
            Normalizer = TextNormalizers[ConvertLegalEntityToAbbreviation]
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
            DestinationColumn = "備考",
            ColumnType = type text,
            Lookup = null,
            Normalizer = TextNormalizers[StripSpacesAndControl]
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
            DestinationColumn = "キャンセル日時",
            ColumnType = type datetime,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "smareji_withdrawal_transaction_id",
            DestinationColumn = "出金取引ID",
            ColumnType = Int64.Type,
            Lookup = null,
            Normalizer = null
        ],
        [
            SourceColumn = "smareji_deposit_transaction_id",
            DestinationColumn = "入金取引ID",
            ColumnType = Int64.Type,
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
        "BankBranchSplit",
        each BankAccountExtraction
            [Extract]
            ([備考], [ゆうちょ銀行区分], [記号番号], [口座種別], [支店番号], [口座番号]),
        type record
    ),
    RemovedOverwrittenColumns = Table.RemoveColumns(
        TableWithBankBranchSplit,
        {"支店番号", "口座番号"}
    ),
    ExpandedTable = Table.ExpandRecordColumn(
        RemovedOverwrittenColumns,
        "BankBranchSplit",
        {"金融機関名", "支店名", "支店番号", "口座番号"},
        {"金融機関名", "支店名", "支店番号", "口座番号"}
    ),
    ReorderedTable = Table.ReorderColumns(
        ExpandedTable,
        List.Transform(ColumnSchema, each [DestinationColumn]) & {"金融機関名", "支店名"}
    )
in
    ReorderedTable

// Assessments
let
    Source = AssessmentsTransform,
    SelectedColumnsTable = Table.SelectColumns(
        Source,
        {
            "買取確定日時",
            "キャンセル日時",
            "店舗CD",
            "査定伝票番号",
            "領収書番号",
            "査定形態",
            "査定ステータス",
            "査定金額",
            "申込者氏名",
            "申込者カナ",
            "支払種別",
            "出金取引ID",
            "入金取引ID",
            "金融機関名",
            "支店名",
            "支店番号",
            "口座種別",
            "口座番号",
            "記号番号",
            "備考"
        },
        MissingField.UseNull
    )
in
    SelectedColumnsTable
