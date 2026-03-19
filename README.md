# MySQL Installer

這個 repository 提供一組以 Shell 為主的自動化腳本，用來在 **Oracle Linux** 環境安裝 MySQL 8.4（Commercial），並可選擇部署 **單機** 或 **InnoDB Cluster**。

> 主要入口腳本：`mysql84_remote_install.sh`

---

## 功能概覽

- 遠端安裝 MySQL 8.4 到一台或多台主機。
- 自動建立部署機與目標主機的 SSH 信任。
- 單機安裝時，會套用不含 Group Replication 參數的設定。
- 多機安裝時，會產生一致的 Group Replication 設定並部署 InnoDB Cluster。
- 內含基本檢查腳本，可用來驗證 mysqld / 連線 / cluster 狀態。

---

## Repository 結構

- `mysql84_remote_install.sh`：遠端安裝主控腳本（建議從這支開始）。
- `mysql_auto_install_2.5.0604.sh`：在目標主機執行的 MySQL 安裝腳本。
- `innodb_cluster_deploy.sh`：跨節點檢查後，觸發 cluster 建置。
- `innodb_cluster_setup.sh`：在 primary 節點用 `mysqlsh` 建立 cluster 並加節點。
- `ssh_trust.sh`：建立 one-way / mutual SSH trust。
- `check.sh`：安裝後檢查 cluster 狀態。
- `initfile_84_template.cnf`：MySQL 設定模板（含 group replication placeholder）。
- `initfile_84.cnf`：實際安裝使用的設定檔。
- `readme.txt`：原始簡版操作說明。

---

## 先決條件

1. 部署機可用 root SSH 登入所有目標主機。
2. 目標主機作業系統需為 Oracle Linux（腳本有檢查）。
3. 需預先準備以下檔案與路徑（相對於 repo root）：
   - `./software/V1047836-01_MySQL_EE_8.4.4_TAR_glibc_2.28.zip`
   - `./software/mysql-router-commercial-8.4.6-1.1.el8.x86_64.rpm`
   - `./software/mysql-shell-commercial-8.4.4-1.1.el8.x86_64.rpm`
   - `./software/zabbix-agent2-7.0.19-release1.el8.x86_64.rpm`
   - `./zabbix/linux_discovery.sh`
   - `./zabbix/userparameter_mysql.conf`
   - `./zabbix/zabbix_agent2.conf`
   - `./zabbix/userparameter_mysqlrouter.conf`
4. 建議先調整密碼與環境參數：
   - `mysql_auto_install_2.5.0604.sh` 內的 `MYSQL_PW`
   - `innodb_cluster_setup.sh` / `innodb_cluster_deploy.sh` 內的 cluster 帳密
   - `zabbix_agent2.conf` 內 zabbix server 設定

---

## 快速開始

### 1) 單機安裝

```bash
./mysql84_remote_install.sh HOST1:INSTANCE1
```

範例：

```bash
./mysql84_remote_install.sh 10.10.10.11:MYDB11
```

### 2) 多機安裝（InnoDB Cluster）

```bash
./mysql84_remote_install.sh HOST1:INSTANCE1 HOST2:INSTANCE2 HOST3:INSTANCE3
```

範例：

```bash
./mysql84_remote_install.sh 10.10.10.11:MYDB11 10.10.10.12:MYDB12 10.10.10.13:MYDB13
```

> 多機模式會先完成每台 MySQL 安裝，再觸發 `innodb_cluster_deploy.sh` 進行 cluster 設定。

---

## 安裝流程（高層）

1. 檢查必要檔案是否存在。
2. 依單機/多機模式產生 `initfile_84.cnf`。
3. 逐台建立 SSH trust（mutual）。
4. 複製安裝檔到遠端 `/opt/software/mysql_installer`。
5. 遠端執行 `mysql_auto_install_2.5.0604.sh`。
6. 若為多機，進一步進行 InnoDB Cluster 部署。
7. 輸出 log 到本地 `./log/`。

---

## 驗證與檢查

可使用 `check.sh` 檢查節點狀態，例如：

```bash
./check.sh 10.10.10.11 10.10.10.12 10.10.10.13
```

它會檢查：
- 遠端 mysqld 行程
- MySQL 連線
- InnoDB Cluster 狀態（需本機可用 `mysqlsh`）

---

## 常見注意事項

- 腳本預設使用 root 遠端操作，請確認資安政策允許。
- 預設帳密（例如 `mysql_123`）僅適合測試，正式環境請先改掉。
- 若 `/etc/hosts` 未正確配置，cluster 部署會被阻擋。
- 多機部署前，建議先確認每台主機 hostname / IP 對應一致。

---

## 參考

原始簡版說明可見 `readme.txt`。
