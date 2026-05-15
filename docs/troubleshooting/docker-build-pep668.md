# Docker 建置時的 PEP 668 錯誤與解決方案

這份文件解釋了在建置 Hermes Agent 的 Docker 映像檔時，可能會遇到的 Python 套件安裝錯誤，以及為什麼我們要在 `Dockerfile` 中使用 `--break-system-packages` 參數。

## 1. 錯誤現象

當我們在基於較新版 Linux（如 Debian 12+、Ubuntu 23.04+）的環境下執行 `pip install` 或 `uv pip install` 時，可能會遇到類似以下的錯誤訊息：

```text
error: The interpreter at /usr is externally managed, and indicates the following:

  To install Python packages system-wide, try apt install
  python3-xyz, where xyz is the package you are trying to
  install.

  If you wish to install a non-Debian-packaged Python package,
  create a virtual environment using python3 -m venv path/to/venv.
  ...

hint: Virtual environments were not considered due to the `--system` flag
```

這個錯誤代表系統拒絕了你將 Python 套件安裝到全域（System-wide）環境的要求。

## 2. 什麼是 PEP 668？

這個錯誤源自於 Python 的一個提案：[PEP 668](https://peps.python.org/pep-0668/) (Marking Python base environments as "externally managed")。

### 為什麼要有這個限制？

在 Linux 系統中，許多作業系統核心工具或預設指令（例如 `apt`、`ufw` 等）都依賴系統內建的 Python 環境。如果開發者隨意使用 `pip install` 安裝或升級全域的 Python 套件，可能會覆蓋掉作業系統依賴的特定版本套件，進而導致系統工具損壞或崩潰。

因此，現代的 Linux 發行版會將系統 Python 標記為「由外部管理（Externally Managed）」，強制要求使用者：

- 使用系統套件管理器（例如 `apt install python3-pandas`）來安裝。
- 使用虛擬環境（`venv`）來隔離專案套件。
- 使用 `pipx` 來安裝獨立的 Python 應用程式。

## 3. 為什麼要在 Docker 中使用 `--break-system-packages`？

雖然 PEP 668 在實體主機上是非常重要的保護機制，但**在 Docker 容器（Container）內，這個限制通常是不必要的**。

### Docker 環境的特殊性

- **已經是隔離環境**：Docker 容器本身就是一個獨立、拋棄式的隔離環境，容器內的改動不會影響到實體主機（Host OS）的作業系統。
- **減少複雜度**：在 Docker 內再建立一層 Python 虛擬環境（`venv`）通常會增加 `Dockerfile` 撰寫的複雜度（例如需要反覆 `source /venv/bin/activate` 或是將虛擬環境的路徑加入 `$PATH`），反而不符合 Docker "One process per container" 的簡單原則。

### `--break-system-packages` 的作用

`--break-system-packages` 是一個明確的覆寫指令（Override flag）。它的作用是告訴 `pip`（或 `uv pip`）：

> 「我知道我正在修改系統層級的 Python 環境，且我願意承擔可能破壞系統套件的風險，請強制幫我安裝。」

因為我們確信自己是在 Docker 容器這個安全沙盒內運作，所以使用這個參數是**安全且標準的實踐方式**。它允許我們略過系統的保護機制，直接將專案所需的套件（如 `requirements.txt` 中的內容）快速安裝到容器的全域環境中供程式使用。

## 4. 總結

- **錯誤原因**：新版 Linux 系統啟用了 PEP 668，禁止直接修改全域 Python 環境以保護系統穩定性。
- **參數作用**：`--break-system-packages` 用來強制略過此保護機制。
- **適用情境**：這個參數**強烈建議只在 Docker 容器**或拋棄式的 CI/CD 環境中使用。在你的個人開發電腦（Mac/Windows/Linux）上，請乖乖使用虛擬環境（`venv`、`conda` 或 `uv venv`）。
