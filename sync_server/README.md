# Pure Live 同步服务器

让安卓和 Windows 共享关注、标签、屏蔽词、观看历史和常用设置。单用户，Go + SQLite。

## 部署

```bash
cd sync_server
echo "SYNC_TOKEN=$(openssl rand -hex 24)" > .env   # 记下这个密钥，App 里要填
docker compose up -d --build
```

服务只监听 `127.0.0.1:8080`，再用已有的反向代理挂到 HTTPS 域名下，例如 Nginx：

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    client_max_body_size 32m;
}
```

检查：`curl https://你的域名/healthz` 返回 `ok`。

数据在 `sync_server/data/sync.db`，备份这个文件即可。

## App 端

设置 → 备份与同步 → 服务器同步，填入 `https://你的域名` 和密钥。打开后，App 启动时会同步一次，本地有改动也会自动同步。

## 协议

`POST /api/v1/sync`，请求头 `Authorization: Bearer <SYNC_TOKEN>`。

```json
{"since": 0, "changes": [{"collection": "favorite", "key": "huya:123", "data": {}, "deleted": false, "updatedAt": 1730000000000}]}
```

返回 `cursor` 之后的所有记录，以及新的 `cursor`。同一条记录按 `updatedAt` 取较新的一方；删除会保留成墓碑，没在线的设备下次同步时也能收到。
