#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IP 生成器 — 把 CIDR 网段 (v4/v6 混合) 展开或抽样成 IP 列表, 供 CFData-Web 使用

用法:
  python3 ipgen.py 网段.txt -o ip.txt                # 全量展开 (v4 每网段限 65536, v6 限 4096)
  python3 ipgen.py 网段.txt -o ip.txt -n 200         # 每个网段随机抽 200 个 (大网段不枚举)
  python3 ipgen.py 网段.txt -o ip.txt -p 443         # 输出 IP:443 格式 (喂 nsb 模式)
  python3 ipgen.py 网段.txt -o sub24.txt --sub24     # v4 输出 /24 粒度 CIDR (替换官方 ips-v4.txt)

网段文件: 每行一个 CIDR, 支持 # 注释、空行、裸 IP (视为 /32 或 /128)
"""
import argparse
import ipaddress
import random
import sys

V4_EXPAND_LIMIT = 1 << 16   # v4 全量展开上限 65536
V6_EXPAND_LIMIT = 1 << 12   # v6 全量展开上限 4096


def parse_net(line):
    line = line.strip()
    if not line or line.startswith('#'):
        return None
    return ipaddress.ip_network(line, strict=False)


def expand_ips(net):
    """全量展开 (小网段)"""
    n = net.num_addresses
    if n > (V4_EXPAND_LIMIT if net.version == 4 else V6_EXPAND_LIMIT):
        return None  # 太大, 调用方决定
    return list(net.hosts()) if n > 2 else list(net)


def sample_ips(net, k):
    """从网段抽 k 个地址; 小网段先展开再抽 (无重复), 大网段直接随机生成"""
    ips = expand_ips(net)
    if ips is not None:
        return random.sample(ips, min(k, len(ips)))
    n = net.num_addresses
    if net.version == 4:
        base = int(net.network_address)
        return [ipaddress.IPv4Address(base + random.randint(1, n - 2)) for _ in range(k)]
    base = int(net.network_address)
    bits = net.max_prefixlen - net.prefixlen
    return [ipaddress.IPv6Address(base + random.getrandbits(bits)) for _ in range(k)]


def main():
    ap = argparse.ArgumentParser(description='CIDR 网段 → IP 列表生成器 (v4/v6)')
    ap.add_argument('input', help='网段文件, 每行一个 CIDR (支持 # 注释/空行/裸 IP)')
    ap.add_argument('-o', '--output', default='-', help='输出文件 (默认 stdout)')
    ap.add_argument('-n', '--sample', type=int, default=0, help='每网段随机抽 N 个 (默认 0 = 全量展开)')
    ap.add_argument('-p', '--port', type=int, default=0, help='给每个 IP 追加 :端口 (喂 nsb 模式用)')
    ap.add_argument('--sub24', action='store_true', help='v4 网段输出为 /24 粒度 CIDR (替换官方 ips-v4.txt 用)')
    ap.add_argument('--seed', type=int, default=None, help='随机种子 (可复现结果)')
    args = ap.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    out = sys.stdout if args.output == '-' else open(args.output, 'w')
    count = 0
    v6warned = False
    try:
        with open(args.input) as f:
            for line in f:
                net = parse_net(line)
                if net is None:
                    continue
                if args.sub24 and net.version == 4:
                    for sub in net.subnets(new_prefix=24):
                        out.write(str(sub) + '\n')
                        count += 1
                    continue
                if args.sample:
                    ips = sample_ips(net, args.sample)
                else:
                    ips = expand_ips(net)
                    if ips is None:
                        sys.stderr.write(f"[ipgen] 警告: {net} 共 {net.num_addresses} 个地址过大, 跳过 (改用 -n 抽样)\n")
                        continue
                for ip in ips:
                    if args.port and ip.version == 6:
                        if not v6warned:
                            sys.stderr.write("[ipgen] 警告: v6 地址忽略 -p 端口 (CFData-Web nsb 解析器不支持 v6 显式端口), 输出裸地址, 默认端口由 nsbtls 决定\n")
                            v6warned = True
                        out.write(str(ip) + '\n')
                    else:
                        out.write(f"{ip}:{args.port}\n" if args.port else f"{ip}\n")
                    count += 1
    finally:
        if out is not sys.stdout:
            out.close()
    sys.stderr.write(f"[ipgen] 完成, 共 {count} 行\n")


if __name__ == '__main__':
    main()
