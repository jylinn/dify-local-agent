# Dify Local Agent — 地端 LLM 自動化市場分析 Agent

用 **Dify + Ollama** 在自己的電腦上做出一個每天自動執行的 AI agent。它會先搜尋當天的財經新聞，產生一份比特幣走勢分析報告，隔天再回頭檢討昨天的預測，並把檢討結果當成「記憶」，用在下一次的分析。全程使用地端模型，不呼叫任何雲端 LLM API。

*A self-hosted LLM agent built with Dify and Ollama: it searches daily news with tool plugins, writes a market-analysis report, then reviews its own previous prediction and feeds that reflection back as memory. Running it for weeks exposed a concrete failure mode: hallucinated reflections that poison the agent's own memory.*

> ⚠️ 這是學習 LLM agent 架構的實驗專案，報告內容**不是投資建議**，而且如下面「觀察」一節所述，內容經常與事實不符。

## 架構

```
                       ┌──────────── Dify 1.14.1（Docker Compose）────────────┐
 每天早上自動觸發 ───▶ │                                                       │
                       │  ① 檢討節點：比較昨天的預測與實際走勢 → 寫檢討報告      │
                       │        │                                              │
                       │        ▼ 讀取歷史檢討（agent 的長期記憶）                │
                       │  ② 搜尋節點：Tavily / DuckDuckGo 外掛抓當天新聞         │
                       │        │                                              │
                       │        ▼                                              │
                       │  ③ LLM 節點：新聞 + 歷史教訓 → 量化走勢預測 + 風險提示   │
                       │        │                                              │
                       │        ▼                                              │
                       │  ④ Code 節點（sandbox）：寫入檔案                       │
                       └────────┼──────────────────────────────┼──────────────┘
                                │ /mnt/d/AI_data（掛載）          │ Ollama 外掛
                                ▼                               ▼
                    D:\AI_data\forecast_日期.txt      Ollama ── Llama 3.1 8B（Q4）
                    D:\AI_data\review_日期.txt         RTX 3050 8 GB
```

（工作流程的節點順序是依照輸出檔案的內容與時間整理出來的。）

| 元件 | 用途 |
|---|---|
| **Dify 1.14.1** | 開源 LLM 應用平台，用 Docker Compose 自架，以視覺化工作流程串接各個節點 |
| **Ollama 外掛 0.1.5** | 讓 Dify 呼叫本機 GPU 上的模型 |
| **Tavily 0.1.12、DuckDuckGo 0.0.13 外掛** | agent 的搜尋工具，用來抓即時新聞 |
| **Llama 3.1 8B（GGUF + 自訂 Modelfile）** | 自己改寫 chat template，讓模型輸出 Dify 能解析的工具呼叫格式（見 [`config/Modelfile.llama31-tools`](config/Modelfile.llama31-tools)） |
| **自訂 sandbox** | 換成 Python 環境較完整的 sandbox image，並把 `D:\AI_data` 掛進容器，讓工作流程可以讀寫主機上的檔案（見 [`config/docker-compose.customizations.yaml`](config/docker-compose.customizations.yaml)） |
| **`listen.ps1`** | 早期的另一種寫檔方式：在 `127.0.0.1:9999` 開一個只收一次資料的 HTTP 接收端，收到報告後寫進 D 槽並自動關閉 |

## 執行紀錄

這個 agent 實際跑了兩段時間：**2026-05-23～06-10**，以及 **2026-10-05～10-13**，每天早上約 07:30 產生一份報告。所有輸出都保留在 [`samples/`](samples/)：

- [`samples/forecasts/`](samples/forecasts/)：21 份每日分析報告（今日核心消息、量化走勢預測、潛在風險提示）
- [`samples/reviews/`](samples/reviews/)：20 份自我檢討報告

## 觀察：自我檢討機制反而污染了 agent 的記憶

長時間執行後，從輸出可以看到 LLM agent 的幾個典型問題。這也是我後來轉向 **AI agent 資安研究**的起點：

1. **新聞沒有落地（ungrounded）**：報告裡的「今日核心消息」常常是籠統、甚至自相矛盾的敘述。例如 10/13 的報告同一段同時寫「市場預期美元強勢」和「市場預期美元疲弱」，代表模型沒有真正依據搜尋結果，而是自己補完內容。
2. **檢討報告捏造數字**：05/23 的檢討先寫「我預測股價會上漲 2%，但實際上下跌了 3%」，同一份報告後面又變成「導致股價下跌 5%」。比特幣的分析卻出現「股價」，數字前後也對不上。
3. **錯誤被寫進記憶，再影響下一次**：檢討報告會被當作「歷史教訓」餵給隔天的分析。所以捏造的教訓會一直傳下去，形成**自我記憶投毒（self-inflicted memory poisoning）**。每份預測都說自己「結合歷史教訓」，但那些教訓本身就可能是錯的。

這和學術界研究的 agent 記憶攻擊是同一個弱點，只是這裡的污染來源是模型自己，不是攻擊者：

- OWASP Agentic AI Threats v1.0 — **T1 Memory Poisoning**
- Chen et al., *AgentPoison*, NeurIPS 2024；Dong et al., *MINJA*（memory injection attack）, arXiv:2503.03704
- CSA MAESTRO 架構中的 **L2 Data Operations**（向量資料庫、記憶）

**可以改進的方向**：每一句「事實」都要附上新聞來源連結；檢討時改用真實的價格 API 數字，不讓模型自己估；寫進記憶之前先做一致性檢查，或交給第二個模型驗證。

## 資安注意事項（自架 Dify 時發現的）

| 項目 | 風險 | 建議 |
|---|---|---|
| Dify `.env` 沿用官方範例 | 資料庫、Redis、sandbox 都是公開的預設密碼 | 部署前用 `openssl rand -base64 42` 產生 `SECRET_KEY` 和各個密碼 |
| sandbox `enable_network: True` | 工作流程的 Code 節點可以連外網，被 prompt injection 時可能把資料傳出去 | 只在需要時開啟，或透過 ssrf_proxy 限制目的地 |
| 主機資料夾掛進 sandbox | 容器裡執行的程式碼可以讀寫 `D:\AI_data` | 只掛專用的資料夾，不要掛整個磁碟 |
| Ollama 開放 `0.0.0.0` 讓容器連線 | API 沒有驗證，區網任何人都能使用 | 用防火牆限制只允許 Docker 網段 |

## 重建方式

```powershell
# 1. 取得 Dify 官方原始碼
git clone https://github.com/langgenius/dify.git
cd dify\docker
copy .env.example .env          # 記得改掉預設密碼
# 2. 套用 config/docker-compose.customizations.yaml 的修改
docker compose up -d
# 3. 建立支援工具呼叫的 Llama 3.1 模型（需要先下載 Llama 3.1 8B 的 GGUF 檔）
ollama create llama31-tools -f config\Modelfile.llama31-tools
# 4. 在 Dify 安裝 Ollama、Tavily、DuckDuckGo 外掛，Base URL 填 http://host.docker.internal:11434
```

## 專案結構

```
dify-local-agent/
├── config/
│   ├── Modelfile.llama31-tools              Llama 3.1 自訂 chat template（支援工具呼叫）
│   ├── docker-compose.customizations.yaml   對官方 compose 的修改：sandbox、掛載、log 輪替
│   └── sandbox-config.yaml                  Dify sandbox 設定
├── scripts/
│   └── listen.ps1                           本機一次性 HTTP 接收端，把報告寫進 D 槽
└── samples/
    ├── forecasts/                           21 份每日報告
    └── reviews/                             20 份自我檢討報告
```

## 學到的技能

- **LLM 應用平台**：Dify 自架（Docker Compose）、工作流程設計、外掛（模型供應商、搜尋工具）
- **Agent 設計**：工具呼叫（tool calling）、反思與記憶（reflection memory）、定時自動執行
- **模型客製化**：Ollama Modelfile、GGUF、chat template 與 stop token
- **容器與系統整合**：Docker volume 掛載、容器連到主機網路、log 輪替、PowerShell `HttpListener`
- **AI 資安觀點**：agent 記憶投毒、幻覺傳遞、自架平台的預設密碼與 sandbox 風險

## 授權

本專案自己撰寫的設定與腳本以 MIT License 釋出。Dify 屬於 LangGenius（Dify Open Source License），Llama 3.1 屬於 Meta（Llama 3.1 Community License），兩者都不包含在本專案中。
