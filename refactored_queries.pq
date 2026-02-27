// ============================================================
// クエリ① fn_ParseBankInfo （新規：共通関数として抽出）
// ============================================================
// 金融機関マスタ・買取の両方で使われていた ParseBankInfo を
// 単一のクエリとして定義し、重複を排除する。
// ※ Power Query エディタで「接続のみ」に設定すること。
let
    BANK_KEYWORDS   = {"農業協同組合", "労働金庫", "信用金庫", "信用組合", "銀行"},
    BRANCH_KEYWORDS = {"営業部", "出張所", "代理店", "本店", "本所", "支店", "支所"},

    SplitByKeyword = (inputText as text, keywords as list) as record =>
        let
            matched = List.First(
                List.Select(keywords, each Text.Contains(inputText, _))
            ),
            pos =
                if matched <> null then
                    Text.PositionOf(inputText, matched) + Text.Length(matched)
                else
                    0
        in
            if matched = null then
                [Name = null, Remainder = inputText]
            else
                [
                    Name      = Text.Start(inputText, pos),
                    Remainder = Text.Middle(inputText, pos)
                ],

    Func = (rawName as nullable text, isJapanPost as nullable logical) as record =>
        let
            clean = if rawName = null then "" else Text.Remove(rawName, {" ", "　"}),
            isJP  = (isJapanPost = true) or Text.Contains(clean, "ゆうちょ")
        in
            if isJP then
                [BankName = "ゆうちょ銀行", BranchName = null]
            else
                let
                    bank   = SplitByKeyword(clean, BANK_KEYWORDS),
                    branch = SplitByKeyword(bank[Remainder], BRANCH_KEYWORDS)
                in
                    [BankName = bank[Name], BranchName = branch[Name]]
in
    Func


// ============================================================
// クエリ② 金融機関コード取得
// ============================================================
let
    // --- 文字列正規化 ---
    FullWidthChars = "ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ０１２３４５６７８９",
    HalfWidthChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",

    ToHalfWidth = (t as text) as text =>
        List.Accumulate(
            List.Zip({Text.ToList(FullWidthChars), Text.ToList(HalfWidthChars)}),
            t,
            (s, pair) => Text.Replace(s, pair{0}, pair{1})
        ),

    // 金融機関名の正規化（マッチング用）
    BankNameReplacements = {
        {"銀行", ""}, {"信用金庫", "信金"}, {"信用組合", "信組"},
        {"労働金庫", "労金"}, {"農業協同組合", "農協"}
    },

    NormalizeBankName = (name as nullable text) as text =>
        if name = null then ""
        else List.Accumulate(
            BankNameReplacements, ToHalfWidth(name),
            (cur, pair) => Text.Replace(cur, pair{0}, pair{1})
        ),

    // 支店名の正規化（マッチング用）
    NormalizeBranchName = (name as nullable text) as text =>
        if name = null then "" else Text.Replace(name, "支店", ""),

    // --- マスタデータ取得 ---
    BanksJson = Json.Document(
        Binary.Buffer(
            Web.Contents(
                "https://raw.githubusercontent.com",
                [RelativePath = "zengin-code/source-data/master/data/banks.json"]
            )
        )
    ),

    BankTable = Table.Buffer(
        let
            recs = List.Transform(
                Record.FieldNames(BanksJson),
                each [
                    code     = Record.Field(BanksJson, _)[code],
                    nameHalf = ToHalfWidth(Record.Field(BanksJson, _)[name])
                ]
            )
        in
            Table.SelectColumns(Table.FromRecords(recs), {"code", "nameHalf"})
    ),

    // --- 支店データ取得 ---
    FetchBranches = (bankCode as text) as table =>
        let
            raw = Json.Document(
                Binary.Buffer(
                    Web.Contents(
                        "https://raw.githubusercontent.com",
                        [RelativePath = "zengin-code/source-data/master/data/branches/" & bankCode & ".json"]
                    )
                )
            ),
            recs = List.Transform(
                Record.FieldNames(raw),
                each [
                    code     = Record.Field(raw, _)[code],
                    name     = Record.Field(raw, _)[name],
                    bankCode = bankCode
                ]
            ),
            tbl = Table.FromRecords(recs, type table [code = text, name = text, bankCode = text])
        in
            Table.AddColumn(tbl, "branchKey", each NormalizeBranchName([name]), type text),

    // --- メイン関数 ---
    Func = (inputTable as table, bankNameCol as text, branchNameCol as text) as table =>
        let
            // 金融機関コードの結合
            WithBankKey  = Table.AddColumn(inputTable, "_BK",
                each NormalizeBankName(Record.Field(_, bankNameCol)), type text),
            JoinedBank   = Table.NestedJoin(
                WithBankKey, {"_BK"}, BankTable, {"nameHalf"}, "_BankMatch", JoinKind.LeftOuter),
            WithBankCode = Table.ExpandTableColumn(
                JoinedBank, "_BankMatch", {"code"}, {"金融機関コード"}),

            // 該当する金融機関の支店データを一括取得
            UniqueBankCodes = List.Distinct(
                List.RemoveNulls(Table.Column(WithBankCode, "金融機関コード"))),
            AllBranches = Table.Buffer(
                Table.Combine(List.Transform(UniqueBankCodes, each FetchBranches(_)))),

            // 支店コードの結合
            WithBranchKey  = Table.AddColumn(WithBankCode, "_BrK",
                each NormalizeBranchName(Record.Field(_, branchNameCol)), type text),
            JoinedBranch   = Table.NestedJoin(
                WithBranchKey, {"金融機関コード", "_BrK"},
                AllBranches,   {"bankCode", "branchKey"},
                "_BranchMatch", JoinKind.LeftOuter),
            WithBranchCode = Table.ExpandTableColumn(
                JoinedBranch, "_BranchMatch", {"code"}, {"支店コード"})
        in
            Table.RemoveColumns(WithBranchCode, {"_BK", "_BrK"})
in
    Func


// ============================================================
// クエリ③ 買取DB
// ============================================================
let
    BaseURL  = "https://api.reuse.ishibashi.co.jp",
    Path     = "api/v1/admin/assessments/",
    PageSize = 256,
    ApiKey   = "ff204072fa23480094d062f67bc35cff",

    ResponseColumns = Excel.CurrentWorkbook(){[Name = "取得列"]}[Content][column_name],

    TotalCount = Json.Document(
        Web.Contents(BaseURL, [
            RelativePath = Path,
            Query   = [#"limit" = Text.From(PageSize)],
            Headers = [#"X-API-KEY" = ApiKey],
            Content = Text.ToBinary("{}")
        ])
    )[meta][total],

    PageCount = Number.RoundDown(TotalCount / PageSize) + 1,

    FetchPage = (pageNum as number) as list =>
        Json.Document(
            Web.Contents(BaseURL, [
                RelativePath = Path,
                Query   = [#"limit" = Text.From(PageSize), #"page" = Text.From(pageNum)],
                Headers = [#"X-API-KEY" = ApiKey],
                Content = Text.ToBinary("{}")
            ])
        )[data],

    Pages        = Table.FromList({1..PageCount}, Splitter.SplitByNothing(), {"PageNumber"}),
    WithData     = Table.AddColumn(Pages, "RawData", each FetchPage([PageNumber])),
    ExpandedList = Table.ExpandListColumn(
        Table.RemoveColumns(WithData, {"PageNumber"}), "RawData")
in
    Table.ExpandRecordColumn(ExpandedList, "RawData", ResponseColumns)


// ============================================================
// クエリ④ 金融機関マスタ
// ============================================================
let
    Source = 買取DB,

    // 金融機関名・支店名をパースして展開
    WithBankInfo = Table.ExpandRecordColumn(
        Table.AddColumn(Source, "BI", each fn_ParseBankInfo([bank_name], [is_japan_post_bank])),
        "BI", {"BankName", "BranchName"}, {"金融機関名", "支店名"}
    ),

    // 金融機関名が取得できた行のみ、重複を除去
    Distinct = Table.Distinct(
        Table.SelectColumns(
            Table.SelectRows(WithBankInfo, each [金融機関名] <> null),
            {"金融機関名", "支店名"}
        )
    ),

    // 金融機関コード・支店コードを取得
    WithCodes = 金融機関コード取得(Distinct, "金融機関名", "支店名")
in
    Table.TransformColumnTypes(
        Table.SelectColumns(WithCodes, {"金融機関名", "支店名", "金融機関コード", "支店コード"}),
        {{"金融機関コード", Int64.Type}, {"支店コード", Int64.Type}}
    )


// ============================================================
// クエリ⑤ 買取
// ============================================================
let
    // --- ルックアップマップ構築 ---
    BuildLookupMap = (tableName as text, keyCol as text, valCol as text) as record =>
        let
            src   = Excel.CurrentWorkbook(){[Name = tableName]}[Content],
            clean = Table.SelectRows(
                Table.Distinct(src, {keyCol}), each Record.Field(_, keyCol) <> null)
        in
            Record.FromList(Table.Column(clean, valCol), Table.Column(clean, keyCol)),

    MapAssessmentType = BuildLookupMap("買取形態", "assessment_type", "買取形態"),
    MapStatus         = BuildLookupMap("ステータス", "status", "ステータス"),
    MapStore          = BuildLookupMap("店舗", "store_id", "店舗CD"),
    MapPaymentType    = BuildLookupMap("支払種別", "payment_type", "支払種別"),
    MapAccountType    = BuildLookupMap("口座種別", "account_type", "口座種別"),

    // --- ヘルパー関数 ---
    Lookup = (map as record, key as any) as any =>
        if key = null then null else Record.FieldOrDefault(map, key, null),

    ToJST = (dtz as nullable datetimezone) as nullable datetime =>
        if dtz = null then null
        else DateTimeZone.RemoveZone(DateTimeZone.SwitchZone(dtz, 9)),

    SafeToJST = (val as any) as nullable datetime =>
        ToJST(try DateTimeZone.From(val) otherwise null),

    CORPORATE_ABBR = {
        [Target = "カブシキガイシャ", Abbr = "カ"],
        [Target = "ユウゲンガイシャ", Abbr = "ユ"],
        [Target = "ゴウドウガイシャ", Abbr = "ゴ"]
    },

    FormatCorporateName = (name as nullable text) as nullable text =>
        if name = null then null
        else List.Accumulate(CORPORATE_ABBR, name, (cur, r) =>
            if Text.StartsWith(cur, r[Target]) then
                r[Abbr] & "）" & Text.Middle(cur, Text.Length(r[Target]))
            else if Text.EndsWith(cur, r[Target]) then
                Text.Start(cur, Text.Length(cur) - Text.Length(r[Target])) & "（" & r[Abbr]
            else
                Text.Replace(cur, r[Target], "（" & r[Abbr] & "）")
        ),

    // --- データ取得 ---
    Source = 買取DB,

    // --- マッピング列の追加 ---
    S1 = Table.AddColumn(Source, "買取形態",
        each Lookup(MapAssessmentType, [assessment_type]), type nullable text),
    S2 = Table.AddColumn(S1, "ステータス",
        each Lookup(MapStatus, [status]), type nullable text),
    S3 = Table.AddColumn(S2, "支払種別",
        each Lookup(MapPaymentType, [payment_type]), type nullable text),
    S4 = Table.AddColumn(S3, "店舗",
        each Lookup(MapStore, [store_id])),
    S5 = Table.AddColumn(S4, "口座種別",
        each Lookup(MapAccountType, [account_type]), type nullable text),

    // --- 日時変換 ---
    S6 = Table.AddColumn(S5, "買取確定日時",
        each SafeToJST([assessment_confirmation_datetime]), type nullable datetime),
    S7 = Table.AddColumn(S6, "買取取消日時",
        each SafeToJST([assessment_cancellation_datetime]), type nullable datetime),

    // --- 氏名処理 ---
    S8 = Table.AddColumn(S7, "申込者氏名",
        each Text.Remove([name], {" ", "　"}), type nullable text),
    S9 = Table.AddColumn(S8, "申込者氏名カナ",
        each FormatCorporateName([name_kana]), type nullable text),

    // --- 金融機関・支店名のパース ---
    S10 = Table.ExpandRecordColumn(
        Table.AddColumn(S9, "BI", each fn_ParseBankInfo([bank_name], [is_japan_post_bank])),
        "BI", {"BankName", "BranchName"}, {"金融機関名", "支店名"}
    ),

    // --- 金融機関マスタとの結合 ---
    MasterData = try Excel.CurrentWorkbook(){[Name = "金融機関マスタ"]}[Content]
                 otherwise #table({"金融機関名", "支店名", "金融機関コード", "支店コード"}, {}),

    JoinedMaster = Table.ExpandTableColumn(
        Table.NestedJoin(
            S10, {"金融機関名", "支店名"},
            MasterData, {"金融機関名", "支店名"},
            "_Master", JoinKind.LeftOuter),
        "_Master",
        {"金融機関コード", "支店コード"},
        {"金融機関番号", "取得支店コード"}
    ),

    // 支店番号：元データが null の場合のみマスタから補完
    WithBranchNum = Table.AddColumn(JoinedMaster, "支店番号",
        each if [branch_number] = null and [取得支店コード] <> null
             then try Int64.From([取得支店コード]) otherwise null
             else [branch_number],
        Int64.Type),

    // --- 最終出力 ---
    OUTPUT_COLUMNS = {
        "買取確定日時", "買取取消日時", "買取形態", "ステータス", "支払種別", "店舗",
        "assessment_slip_number", "receipt_number", "assessment_total_price_including_tax",
        "申込者氏名", "申込者氏名カナ", "金融機関名", "支店名", "金融機関番号",
        "支店番号", "口座種別", "account_number", "branch_and_account_number_of_japan_post_bank"
    },

    RENAME_MAP = {
        {"assessment_slip_number", "査定伝票番号"},
        {"receipt_number", "領収書番号"},
        {"assessment_total_price_including_tax", "査定金額税込"},
        {"account_number", "口座番号"},
        {"branch_and_account_number_of_japan_post_bank", "記号番号"}
    },

    COLUMN_TYPES = {
        {"買取確定日時", type nullable datetime}, {"買取取消日時", type nullable datetime},
        {"買取形態", type nullable text}, {"ステータス", type nullable text},
        {"支払種別", type nullable text}, {"店舗", Int64.Type},
        {"査定伝票番号", Int64.Type}, {"領収書番号", Int64.Type},
        {"査定金額税込", Int64.Type}, {"申込者氏名", type nullable text},
        {"申込者氏名カナ", type nullable text}, {"金融機関名", type nullable text},
        {"支店名", type nullable text}, {"金融機関番号", Int64.Type},
        {"支店番号", Int64.Type}, {"口座種別", type nullable text},
        {"口座番号", Int64.Type}, {"記号番号", type nullable text}
    }
in
    Table.TransformColumnTypes(
        Table.RenameColumns(
            Table.SelectColumns(WithBranchNum, OUTPUT_COLUMNS),
            RENAME_MAP),
        COLUMN_TYPES
    )
