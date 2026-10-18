#!/usr/bin/env python3
"""check-privacy — 发布前隐私自检：扫描「被 git 跟踪的文件」里的
本机绝对路径 / 私有工作区名 / 凭据形态。

判据是逐文件字节正则（等价 `grep -a -c`；`strings` 会把嵌在长串里的路径切断，漏报）。
命中分两类：
  - 真泄漏：本机家目录路径（/Users/<user>/…）、私有工作区/仓库名、凭据形态
    （sk-/ghp_/AKIA/PEM 私钥头）、真实交易 ID 形态（17 位纯大写字母数字，
    PayPal 订单号/捕获 ID 的形状——文档与文案只允许用虚构示例）
  - 已登记例外（ALLOW）：有意为之的文档占位符、公开仓库地址与虚构示例 ID。
    新增例外必须在这里登记并写理由，否则守卫下次照样红——登记即声明「这行我审过」。

用法：make check-privacy（或 python3 scripts/check-privacy.py）
退出码 0 = 干净；1 = 有命中（make test 已内含本检查）。
"""
import os
import re
import subprocess
import sys

SELF = os.path.basename(__file__)

# (正则, 说明)——按风险排序。
# 私有工作区/仓库名故意拆成拼接写法：本文件自身会上公开仓库，逐字包含这些名字
# 本身就是泄漏；拼接后运行时才组合，扫描功能不变。
NEEDLES = [
    (re.compile(rb'/(Users|home)/[A-Za-z0-9_.-]+/'), '本机家目录绝对路径'),
    (re.compile(rb'[A-Za-z]:\\\\?[Uu]sers\\\\?[A-Za-z0-9_.-]+'), 'Windows 本机路径'),
    (re.compile(rb'Workspace/' + b'CNB'), '私有工作区根目录名'),
    (re.compile(rb'individular' + b'-invest'), '私有仓库名'),
    (re.compile(rb'erishen'), '本机用户名（公开 GitHub 地址除外，见 ALLOW）'),
    (re.compile(rb'\bsk-[A-Za-z0-9_-]{20,}'), 'OpenAI 形态密钥'),
    (re.compile(rb'\bghp_[A-Za-z0-9]{20,}'), 'GitHub PAT'),
    (re.compile(rb'\bAKIA[0-9A-Z]{16}'), 'AWS Access Key'),
    (re.compile(rb'PRIVATE KEY'), 'PEM 私钥头'),
    (re.compile(rb'\b[0-9A-Z]{17}\b'), '真实交易 ID 形态（PayPal 订单号/捕获 ID 形状）'),
    (re.compile(rb'SHOP-1-[0-9]{6,}'), '真实店面订单号形态（本机实例生成，公开仓只允许虚构示例）'),
]

# 行级例外（正则, 理由）。只放「审过的、有意为之的」。
ALLOW = [
    (re.compile(rb'/Users/you/'), 'README/.env.example 的文档占位符（中性用户名 you）'),
    (re.compile(rb'E:/[Ww]orkspace/'), 'README 的 Windows 文档占位符'),
    (re.compile(rb'github(\.com|usercontent\.com)/erishen'), '公开仓库地址（lume-core 为公开 repo）'),
    (re.compile(rb'erishen/lume-core'), 'README 变量表里的公开仓库引用'),
    (re.compile(rb'1AB23456CD7890123|2CD34567DE8901234'), 'base.lume 恢复页文案的虚构示例 ID（递増序列，一眼可辨非真实交易）'),
]


def tracked_files():
    out = subprocess.run(['git', 'ls-files', '-z'], capture_output=True)
    if out.returncode != 0:
        print('check-privacy: ERROR git ls-files failed:', out.stderr.decode())
        sys.exit(2)
    return [f for f in out.stdout.decode('utf-8', 'surrogateescape').split('\0') if f]


def main():
    fail = 0
    files = tracked_files()
    for f in files:
        if os.path.basename(f) == SELF:
            continue  # 本脚本必须包含 needle 字面量才能扫描
        if not os.path.isfile(f):
            continue
        try:
            with open(f, 'rb') as fh:
                data = fh.read()
        except OSError as e:
            print('check-privacy: SKIP %s (%s)' % (f, e))
            continue
        for lineno, line in enumerate(data.split(b'\n'), 1):
            hit = next((d for pat, d in NEEDLES if pat.search(line)), None)
            if not hit:
                continue
            if any(a.search(line) for a, _ in ALLOW):
                continue
            print('check-privacy: HIT %s:%d [%s] %r' % (f, lineno, hit, line.strip()[:100]))
            fail = 1
    if fail:
        print('check-privacy: FAIL (%d tracked files scanned)' % len(files))
        return 1
    print('check-privacy: ok (%d tracked files scanned, 0 hits)' % len(files))
    return 0


if __name__ == '__main__':
    sys.exit(main())
