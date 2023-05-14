FROM alpine:3.17 as builder

ARG ZT_PORT
ENV TZ=Asia/Shanghai
WORKDIR /app

# 修改软件源为国内镜像
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories 

# 安装依赖包
RUN apk update && apk add --no-cache git python3 npm make g++ zerotier-one \
    && mkdir -p /usr/include/nlohmann/ && cd /usr/include/nlohmann/ \
    && wget https://ghproxy.markxu.online/https://github.com/nlohmann/json/releases/download/v3.10.5/json.hpp \
    && npm install -g node-gyp

# 下载ztncui源码并安装依赖包
RUN git clone https://ghproxy.markxu.online/https://github.com/key-networks/ztncui.git \
    && cd /app/ztncui/src \
    && cp /app/patch/binding.gyp . \
    && npm install \
    && echo 'HTTP_PORT=3443' >.env \
    && echo 'NODE_ENV=production' >>.env \
    && echo 'HTTP_ALL_INTERFACES=true' >>.env \
    && echo "ZT_ADDR=localhost:${ZT_PORT}" >>.env\
    && echo "${ZT_PORT}" >/app/zerotier-one.port \
    && cp -v etc/default.passwd etc/passwd \
    && rm -rf /root/.npm /root/.node-gyp /usr/lib/node_modules/npm 

# 下载ZeroTierOne源码并生成planet二进制文件
RUN git clone -v https://ghproxy.markxu.online/https://github.com/zerotier/ZeroTierOne.git --depth 1 \
    && zerotier-one -d && sleep 5s && ps -ef |grep zerotier-one |grep -v grep |awk '{print $1}' |xargs kill -9 \
    && cd /var/lib/zerotier-one && zerotier-idtool initmoon identity.public >moon.json\
    && cd /app/patch && python3 patch.py \
    && cd /var/lib/zerotier-one && zerotier-idtool genmoon moon.json && mkdir moons.d && cp ./*.moon ./moons.d \
    && cd /app/ZeroTierOne/attic/world/ && sh build.sh \
    && sleep 5s \
    && cd /app/ZeroTierOne/attic/world/ && ./mkworld \
    && mkdir /app/bin -p && cp world.bin /app/bin/planet \
    && rm -rf /root/.npm /root/.node-gyp /usr/lib/node_modules/npm 

# 设置非root用户
RUN addgroup -g 1000 planet && adduser -D -u 1000 -G planet planet \
    && chown planet:planet /var/lib/zerotier-one

COPY --chown=planet:planet ./ /app/
USER planet

FROM alpine:3.17
WORKDIR /app

# 修改软件源为国内镜像
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories 

# 安装依赖包
RUN apk update && apk add --no-cache npm zerotier-one

COPY --from=builder --chown=planet:planet /app/ztncui /app/ztncui
COPY --from=builder --chown=planet:planet /app/bin /app/bin
COPY --from=builder /app/zerotier-one.port /app/zerotier-one.port
COPY --from=builder --chown=planet:planet /var/lib/zerotier-one /var/lib/zerotier-one

VOLUME [ "/app","/var/lib/zerotier-one" ]

USER planet

CMD /bin/sh -c "cd /var/lib/zerotier-one && ./zerotier-one -pcat /app/zerotier-one.port -d; cd /app/ztncui/src;npm start"
