# Role

你是一位資深的 Ruby on Rails 測試基礎架構工程師，精通 RSpec, Capybara 以及現代化的瀏覽器自動化工具。

# Goal

我們目前的 Rails 專案使用 `selenium-webdriver` 進行 System Tests。目標是將其遷移至 `capybara-playwright-driver`，以獲得更穩定且快速的測試體驗。請採用「漸進式整合」的方式，保留 RSpec 和 Capybara 的語法，僅替換底層 Driver。

# Current Context

以下是專案目前的關鍵設定檔案內容：

## 1. Gemfile

(目前依賴 selenium-webdriver)

```ruby
group :test do
  # Use system testing [[https://guides.rubyonrails.org/testing.html#system-testing](https://guides.rubyonrails.org/testing.html#system-testing)]
  gem "capybara", "~> 3.40"
  gem "selenium-webdriver", "~> 4.21"

  # Database cleaner for test isolation [[https://github.com/DatabaseCleaner/database_cleaner](https://github.com/DatabaseCleaner/database_cleaner)]
  gem "database_cleaner-active_record", "~> 2.2"

  # SimpleCov for code coverage [[https://github.com/simplecov-ruby/simplecov](https://github.com/simplecov-ruby/simplecov)]
  gem "simplecov", require: false
end
```

## 2. spec/support/capybara.rb

(目前設定使用 selenium)

```ruby
require "capybara/rspec"

Capybara.configure do |config|
  config.default_max_wait_time = 5
  config.default_normalize_ws = true
end

RSpec.configure do |config|
  config.before(:each, type: :system) do |example|
    if example.metadata[:js]
      driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
    else
      driven_by :rack_test
    end
  end
end

```

## 3. .github/workflows/ci.yml

(CI 流程，目前沒有安裝 Playwright 依賴)

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      # ... (略) ...

```

# Instructions

請依照以下步驟進行重構，並提供修改後的程式碼：

1. **更新 Gemfile**:

* 移除 `gem "selenium-webdriver"`。
* 加入 `gem "capybara-playwright-driver"` 到 `:test` group。

1. **更新 spec/support/capybara.rb**:

* 註冊 Playwright driver (`Capybara.register_driver :playwright ...`)。
* 建議配置：使用 `:chromium`，設定 `headless: true`。
* 修改 `driven_by` 的邏輯，將 `:selenium` 替換為 `:playwright`。
* 保留 `rack_test` 作為非 JS 測試的驅動。

1. **更新 CI 設定 (.github/workflows/ci.yml)**:

* Playwright 需要 Node.js 環境和瀏覽器二進位檔案。
* 在 CI 的 `test` job 中，加入安裝 Playwright 瀏覽器的步驟。
* 提示：可以使用 `playwright-ruby-client` 提供的 CLI 指令，或者直接用 `npx playwright install` (需確保有 Node 環境)。

1. **提供本地安裝指令**:

* 告訴我如何在開發環境（本機）安裝必要的 Playwright 瀏覽器，以便我可以運行測試。

1. **相容性檢查**:

* 請確保修改後的設定能相容於現有的 System Test 寫法（例如 `visit`, `click_on`, `assert_text` 等）。

請先進行架構分析，列出變更計畫，再提供修改後的檔案內容。

```

---

### 💡 這個 Prompt 的設計重點：

1.  **明確的角色 (Role)**：設定 Agent 為專家，確保輸出的程式碼品質。
2.  **上下文注入 (Context)**：直接貼上了您提供的 `Gemfile`、`capybara.rb` 和 `ci.yml` 的片段。這讓 Agent 不需要去猜測您的現有設定，能精準地進行「替換」。
3.  **具體指令 (Instructions)**：
    * 明確指定使用 `capybara-playwright-driver` (這是 Ruby 界的標準接合器)。
    * 特別提到 **CI 環境** 的調整。這是遷移最容易失敗的地方，因為 Playwright 需要額外的系統依賴（瀏覽器 binary）。
    * 要求保留 `rack_test`，這是 Rails 測試效能的最佳實踐（不需要 JS 的測試就用最快的驅動）。
4.  **漸進式策略**：強調「不改變測試語法」，降低遷移恐慌。

### 預期 Agent 的產出結果：

Agent 應該會給您類似以下的變更建議（您可以先預覽）：

**Gemfile:**
```ruby
group :test do
  gem "capybara"
  gem "capybara-playwright-driver" # 新增這個
  # gem "selenium-webdriver" # 移除這個
end

```

**spec/support/capybara.rb:**

```ruby
require 'capybara/rspec'

# 註冊 Driver
Capybara.register_driver :playwright do |app|
  Capybara::Playwright::Driver.new(app,
    browser_type: :chromium,
    headless: true # CI 上必須是 headless
  )
end

RSpec.configure do |config|
  config.before(:each, type: :system) do |example|
    if example.metadata[:js]
      # 關鍵變更：使用 playwright
      driven_by :playwright
    else
      driven_by :rack_test
    end
  end
end

```

**CI 設定 (ci.yml):**
加入 `npm install` (如果專案沒 node_modules) 和 `npx playwright install` 的步驟。
