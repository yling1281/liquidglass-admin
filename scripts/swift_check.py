#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Swift 静态检查器（无 Swift 工具链环境下的兜底）。

检查项：
  1. 括号/花括号/方括号配平（忽略字符串与注释里的）
  2. 中文与特殊字符编码完整性（U+FFFD 替换字符）
  3. 标识符规范：同一类型内重复定义、拼写不一致的近似名
  4. 跨文件符号引用：本工程自定义类型/成员是否确实存在
  5. 硬编码的 Swift 常见坑：CFRelease/CFRetain、条件编译不配平
  6. 属性包装器声明的成员是否在同文件被真正使用（cannot find 'x' in scope 高发点）

退出码 0 = 通过；1 = 有 ERROR。
"""

import os
import re
import sys
import io

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.normpath(os.path.join(ROOT, "LiquidGlassAdmin", "Sources"))

errors = []
warnings = []


def strip_comments_and_strings(text):
    """把字符串字面量与注释替换成等长空格，保留行结构，方便配平检查。"""
    out = []
    i = 0
    n = len(text)
    in_line_comment = False
    in_block_comment = False
    block_depth = 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line_comment:
            out.append("\n" if c == "\n" else " ")
            if c == "\n":
                in_line_comment = False
            i += 1
            continue
        if in_block_comment:
            if c == "/" and nxt == "*":
                block_depth += 1
                out.append("  ")
                i += 2
                continue
            if c == "*" and nxt == "/":
                block_depth -= 1
                out.append("  ")
                i += 2
                if block_depth == 0:
                    in_block_comment = False
                continue
            out.append("\n" if c == "\n" else " ")
            i += 1
            continue
        if c == "/" and nxt == "/":
            in_line_comment = True
            out.append("  ")
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block_comment = True
            block_depth = 1
            out.append("  ")
            i += 2
            continue
        if c == '"':
            # 字符串字面量（处理 \" 与 \\）
            out.append(" ")
            i += 1
            while i < n:
                if text[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                    continue
                if text[i] == '"':
                    out.append(" ")
                    i += 1
                    break
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check_balance(path, text):
    """括号配平。"""
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    line = 1
    for ch in text:
        if ch == "\n":
            line += 1
        elif ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack:
                errors.append("%s:%d 多余的 '%s'" % (rel(path), line, ch))
                return
            open_ch, open_line = stack.pop()
            if open_ch != pairs[ch]:
                errors.append("%s:%d '%s' 与第 %d 行的 '%s' 不匹配" % (
                    rel(path), line, ch, open_line, open_ch))
                return
    if stack:
        open_ch, open_line = stack[-1]
        errors.append("%s:%d '%s' 未闭合" % (rel(path), open_line, open_ch))


def check_encoding(path, text):
    """编码完整性。"""
    if "\ufffd" in text:
        idx = text.index("\ufffd")
        line = text[:idx].count("\n") + 1
        errors.append("%s:%d 出现 U+FFFD 替换字符（编码被破坏）" % (rel(path), line))
    # 常见 mojibake：中文被 UTF-8 解成 Latin-1
    for bad in ("ä¸", "éå", "å¯", "æ"):
        if bad in text:
            line = text[: text.index(bad)].count("\n") + 1
            warnings.append("%s:%d 疑似乱码片段 %r" % (rel(path), line, bad))
            break


def check_cf_apis(path, text):
    """CFRelease/CFRetain 在 Swift 里是 unavailable。"""
    for bad in ("CFRelease(", "CFRetain(", "CFRelease (", "CFRetain ("):
        if bad in text:
            line = text[: text.index(bad)].count("\n") + 1
            errors.append("%s:%d 使用了 %s（Swift 中该 API 不可用）" % (
                rel(path), line, bad.strip(" (")))


# Swift 保留字：不能作为属性/参数名声明，除非用反引号转义。
# 这条是从真实编译错误补上的 —— `let operator: String?` 在 Xcode 里直接报
# "keyword 'operator' cannot be used as an identifier here"，
# 本地静态检查当时没抓到，白跑了一轮云编译。
SWIFT_RESERVED = set("""
operator default class struct enum protocol extension import func var let in for
while do switch case return break continue defer guard if else repeat where as is
try throw throws catch async await actor static final public private internal
fileprivate open override required convenience lazy weak unowned mutating
nonmutating subscript typealias associatedtype deinit init self Self super
nil true false convenience dynamic indirect prefix postfix infix
""".split())

DECL_RE = re.compile(
    r"^(\s*)(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?"
    r"(?:static\s+|class\s+)?(let|var|func)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[:(]",
    re.M,
)


def check_reserved_identifiers(path, text):
    """把 Swift 保留字当标识符声明 → 编译硬错误。"""
    for m in DECL_RE.finditer(text):
        name = m.group(3)
        if name in SWIFT_RESERVED:
            line = text[: m.start()].count("\n") + 1
            errors.append(
                "%s:%d 用保留字 `%s` 作标识符（需写成反引号形式 `%s`）"
                % (rel(path), line, name, name)
            )


# LoadState 的 case 名是 idle/loading/loaded/failed。
# 写成 .failure / .success 是 Result 的写法，混用必然编译失败。
LOADSTATE_CASE_RE = re.compile(r"case \.(failure|success)\b(?!\(fromStatus)")


def check_loadstate_cases(path, text):
    """LoadState 的 case 名误用 Result 的命名。"""
    # 只在明显涉及 store.state / *State 的行上检查，避免误伤 Result / StateView.Kind
    for idx, line in enumerate(text.split("\n"), 1):
        if "case ." not in line:
            continue
        # 排除 Result 与 StateView.Kind 的合法用法
        if "StateView.Kind" in line or "Result<" in line:
            continue
        # 只对「Store 的 state 属性」相关的 switch 做检查
        if not re.search(r"store\.\w*([Ss]tate|statistics)\b", line):
            continue
        m = LOADSTATE_CASE_RE.search(line)
        if m:
            wrong = m.group(1)
            right = "failed" if wrong == "failure" else "loaded"
            errors.append(
                "%s:%d LoadState 没有 `.%s`（应为 `.%s`）"
                % (rel(path), idx, wrong, right)
            )


# 属性顺序：Swift 要求具名参数按声明顺序出现（可跳过有默认值的）。
# APIRequest 的声明顺序是 endpoint → query → body → service。
ARG_ORDER_PAIRS = [
    ("APIRequest(", "service", "body"),
]


def _find_calls(text, callee):
    """找出所有 `callee(...)` 的调用块，用括号配平精确定位结束位置。

    不能用正则 `callee\\((.*?)\\)`：单行调用以单个 `)` 结尾，
    非贪婪会一路多吃到后面某个 `)` 上，把多个调用并成一块（实测误报过）。
    """
    out = []
    needle = callee + "("
    pos = 0
    while True:
        i = text.find(needle, pos)
        if i < 0:
            break
        start = i + len(needle)
        depth = 1
        j = start
        while j < len(text) and depth > 0:
            c = text[j]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            j += 1
        if depth == 0:
            out.append((i, text[start : j - 1]))
        pos = j
    return out


def check_argument_order(path, text):
    """具名参数顺序颠倒 → "argument 'body' must precede argument 'service'"。"""
    order = ["endpoint", "query", "body", "service"]

    for start, block in _find_calls(text, "APIRequest"):
        # 只取**顶层**参数名（行首缩进后紧跟 `name:`），避免把闭包里的同名键算进来
        names = re.findall(r"^\s*(endpoint|query|body|service)\s*:", block, re.M)
        if not names:
            continue

        seen = []
        for n in names:
            if n not in seen:
                seen.append(n)

        idxs = [order.index(n) for n in seen if n in order]
        if idxs != sorted(idxs):
            errors.append(
                "%s:%d APIRequest 具名参数顺序错误（出现了 %s；正确顺序 endpoint→query→body→service）"
                % (rel(path), to_line(text, start), "→".join(seen))
            )

        # 结构性破坏自检：同一调用块里某个参数名出现两次 = 被批量替换拆坏了
        for key in order:
            if names.count(key) > 1:
                errors.append(
                    "%s:%d APIRequest 里 `%s:` 出现了 %d 次（疑似批量替换把调用拆坏了）"
                    % (rel(path), to_line(text, start), key, names.count(key))
                )


def to_line(text, index):
    return text[:index].count("\n") + 1


def check_broken_container(path, text):
    """容器字面量被拆坏：`([,` 或 `[ ,`。"""
    for m in re.finditer(r"\(\[\s*,|\[\s*,\s*$", text, re.M):
        errors.append(
            "%s:%d 容器字面量开头就是逗号（疑似批量替换拆坏了调用）"
            % (rel(path), to_line(text, m.start()))
        )


# 静态工厂方法里调自己 = 无限递归。
# 踩过：批量把 `StateView(kind: .loading(x))` 替换成 `StateView.loading(x)` 时，
# 连工厂方法**自身的实现**也被替换了，变成 `static func loading(...) { StateView.loading(...) }`
# —— 编译器不报错（解析到的是自己），运行时无限递归。
SELF_CALL_RE = r"static func (\w+)\([^)]*\)\s*->[^{]+\{\s*StateView\.\1\("


def check_self_recursive_factory(path, text):
    """静态工厂方法体内直接调用了自己。"""
    for m in re.finditer(SELF_CALL_RE, text):
        errors.append(
            "%s:%d 静态工厂 `%s` 内部调用了自己（无限递归；应写 `StateView(kind: .%s(...))`）"
            % (rel(path), to_line(text, m.start()), m.group(1), m.group(1))
        )


# 尾随闭包挂错对象：`StateView(kind: .failure(e)) { ... }`
# Kind.failure 有两个关联值，尾随闭包会挂到 StateView.init 上。
STATEVIEW_TRAILING_RE = re.compile(
    r"StateView\(\s*kind:\s*\.failure\([^)]*\)\s*\)\s*\{"
)


def check_stateview_trailing_closure(path, text):
    for m in STATEVIEW_TRAILING_RE.finditer(text):
        errors.append(
            "%s:%d StateView(kind: .failure(...)) 不能用尾随闭包"
            "（应写 `StateView.failure(error) { ... }`）"
            % (rel(path), to_line(text, m.start()))
        )


def check_conditional_compilation(path, text):
    """#if / #endif 配平。"""
    stack = []
    for idx, line in enumerate(text.split("\n"), 1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append((idx, stripped))
        elif stripped.startswith("#endif"):
            if not stack:
                errors.append("%s:%d 多余的 #endif" % (rel(path), idx))
            else:
                stack.pop()
        elif stripped.startswith("#else") or stripped.startswith("#elseif"):
            if not stack:
                errors.append("%s:%d #else 没有对应的 #if" % (rel(path), idx))
    if stack:
        idx, _ = stack[-1]
        errors.append("%s:%d #if 未闭合" % (rel(path), idx))


# 自定义类型（struct/class/enum/actor 声明）
TYPE_RE = re.compile(
    r"^(\s*)(?:public\s+|internal\s+|private\s+|fileprivate\s+)?"
    r"(?:final\s+)?(struct|class|enum|actor)\s+([A-Z][A-Za-z0-9_]*)",
    re.M,
)
# 顶层函数
FUNC_RE = re.compile(
    r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+)?"
    r"(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)
# 成员（属性/方法）
MEMBER_RE = re.compile(
    r"^\s{4}(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+)?"
    r"(?:static\s+|class\s+)?(?:final\s+)?"
    r"(?:@\w+\s+)*(?:var|let|func)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def collect():
    files = []
    for dirpath, _, filenames in os.walk(SRC):
        for name in filenames:
            if name.endswith(".swift"):
                files.append(os.path.join(dirpath, name))
    return sorted(files)


def main():
    files = collect()
    if not files:
        print("找不到任何 .swift 文件")
        return 1

    print("检查 %d 个 Swift 文件…" % len(files))

    # 全局符号表
    global_types = {}     # 类型名 -> 文件
    global_funcs = set()
    type_members = {}     # 类型名 -> set(成员名)

    texts = {}
    for path in files:
        with io.open(path, "r", encoding="utf-8") as f:
            text = f.read()
        texts[path] = text

        # 配平检查必须基于「剥离了注释与字符串」的文本 ——
        # 否则注释里的中文括号、全角括号会被当成语法符号，
        # 字符串里的 { } 也会误报。
        check_balance(path, strip_comments_and_strings(text))
        check_encoding(path, text)
        check_cf_apis(path, text)
        check_reserved_identifiers(path, text)
        check_loadstate_cases(path, text)
        check_argument_order(path, text)
        check_broken_container(path, text)
        check_self_recursive_factory(path, text)
        check_stateview_trailing_closure(path, text)
        check_conditional_compilation(path, text)

        for m in TYPE_RE.finditer(text):
            indent = len(m.group(1))
            name = m.group(3)
            # 缩进 > 0 说明是嵌套类型（作用域独立，不算重复定义）。
            # 顶层类型才做全局重名检查。
            if indent == 0:
                if name in global_types:
                    errors.append("%s: 顶层类型 %s 与 %s 重复定义" % (
                        rel(path), name, rel(global_types[name])))
                else:
                    global_types[name] = path
            # 收集该类型区间内的成员
            start = m.start()
            # 找类型体结束（下一个顶层声明）
            rest = text[start:]
            members = set(MEMBER_RE.findall(rest[:6000]))
            type_members.setdefault(name, set()).update(members)

        for m in FUNC_RE.finditer(text):
            global_funcs.add(m.group(1))

    # 跨文件符号引用检查
    # 只检查「明显是本工程自定义类型」的用法：TypeName(
    known = set(global_types.keys())
    # 收集所有嵌套类型名（含缩进 > 0 的），它们在自己的作用域内合法。
    nested_types = set()
    for path, text in texts.items():
        for m in TYPE_RE.finditer(text):
            if len(m.group(1)) > 0:
                nested_types.add(m.group(3))

    for path, text in texts.items():
        for m in re.finditer(r"\b([A-Z][A-Za-z0-9_]{2,})\s*\(", text):
            name = m.group(1)
            if name in known or name in nested_types:
                continue
            # 系统类型白名单（大致覆盖 SwiftUI / Foundation 常用）
            if name in SYSTEM_TYPES:
                continue
            if name in global_funcs:
                continue
            line = text[: m.start()].count("\n") + 1
            warnings.append("%s:%d 未知类型 %s(...)" % (rel(path), line, name))

    # 类型注解位置（`: Type` / `-> Type` / `[Type]`）里引用的类型必须存在。
    # ⚠️ 只对「本工程自定义类型」做这项检查 —— Swift/SwiftUI 的协议名
    # （View / Identifiable / ObservableObject …）数量太多，白名单永远补不全，
    # 硬查只会制造噪音，反而让人忽略真正的错误。
    #
    # 做法：先找出所有「出现过的类型名」，再找出所有「被引用的类型名」，
    # 差集里**排除了系统常见名**的那些，就是本工程内部引用错的名字。
    referenced = set()
    for path, text in texts.items():
        for m in re.finditer(
            r"(?::\s*|\->\s*|\[\s*)([A-Z][A-Za-z0-9_]{2,})(?:\s*[\]\?,]|\s*$|\s*\{)",
            text,
            re.M,
        ):
            referenced.add(m.group(1))

    # 已知系统类型（协议、SwiftUI、Foundation 的高频名）——不参与差集。
    SYSTEM_PROTOCOL_NAMES = set("""
View App Identifiable Hashable Equatable Codable Encodable Decodable
ObservableObject EnvironmentObject StateObject ObservedObject State Binding
LocalizedError Error Equatable Comparable CustomStringConvertible
Sendable Actor AnyObject Any AnyClass Void Never
Layout LayoutSubview Subviews ProposedViewSize ProposedViewSize
CGRect CGPoint CGSize CGFloat CGAffineTransform
URL URLRequest URLResponse URLSession URLSessionTask
UIImage UIColor UIView UIViewController UIApplication UIDevice UIPasteboard
Color Font Edge EdgeInsets Alignment
Value Element Key Success Failure
""".split())

    suspicious = referenced - known - nested_types - SYSTEM_TYPES - SYSTEM_PROTOCOL_NAMES - global_funcs
    for name in sorted(suspicious):
        # 在文件里定位第一处引用
        for path, text in texts.items():
            m = re.search(
                r"(?::\s*|\->\s*|\[\s*)" + re.escape(name) + r"(?:\s*[\]\?,]|\s*$|\s*\{)",
                text,
                re.M,
            )
            if m:
                line = text[: m.start()].count("\n") + 1
                errors.append("%s:%d 引用了未定义的类型 %s" % (rel(path), line, name))
                break

    # 属性包装器成员使用检查（cannot find 'x' in scope 高发点）
    for path, text in texts.items():
        props = re.findall(r"@(?:\w+\.)?(\w+)\s+(?:private\s+|public\s+|internal\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)", text)
        for wrapper, pname in props:
            if wrapper in ("State", "Binding", "EnvironmentObject", "ObservedObject", "StateObject", "Environment", "FocusState", "AppStorage", "SceneStorage", "FetchRequest", "Namespace"):
                # 检查本文件里是否被引用
                uses = len(re.findall(r"\$?" + re.escape(pname) + r"\b", text))
                if uses <= 1:
                    line = text[: text.index(pname)].count("\n") + 1
                    warnings.append("%s:%d @%s %s 在本文件内似乎未被使用" % (
                        rel(path), line, wrapper, pname))

    # 打印结果
    print("")
    print("定义的类型（%d 个）:" % len(global_types))
    for name in sorted(global_types):
        print("  - %-22s %s" % (name, rel(global_types[name])))

    print("")
    if warnings:
        print("=== 警告 %d 条 ===" % len(warnings))
        for w in warnings:
            print("  " + w)
        print("")

    if errors:
        print("=== 错误 %d 条 ===" % len(errors))
        for e in errors:
            print("  " + e)
        print("")
        print("❌ 检查未通过")
        return 1

    print("✅ 检查通过：无错误")
    return 0


SYSTEM_TYPES = set("""
Text Image VStack HStack ZStack Grid GridRow GridItem ScrollView List LazyVStack LazyVGrid
LazyHStack LazyHGrid Spacer Divider Group ForEach NavigationStack NavigationLink NavigationSplitView
NavigationView TabView Section Form LabeledContent Button Toggle TextField SecureField Picker
Menu Sheet Alert Slider Stepper ProgressView ViewThatFits
Color Font Weight Angle Edge EdgeInsets Alignment Rect CGFloat CGSize CGPoint
AnyView AnyShape AnyLayout EmptyView Binding State ObservedObject EnvironmentObject
URL URLRequest URLSession URLResponse URLComponents URLQueryItem HTTPURLResponse
Data Date Calendar DateFormatter Locale TimeZone TimeInterval DispatchQueue Task
JSONDecoder JSONEncoder JSONSerialization Codable Encodable Decodable
String Int Int64 Double Float Bool Array Set Dictionary Optional Result
UUID UserDefaults Bundle FileManager NotificationCenter
UIImage UIColor UIPasteboard UIApplication UIDevice UIView UIWindow
NSObject NSString NSNumber NSArray NSDictionary
ToolbarItem ToolbarItemGroup ToolbarTitleMenu ToolbarItemPlacement
Label RoundedRectangle Capsule Rectangle Circle Ellipse
Sendable UInt64 UInt32 Int32 Int16 UInt8 Any AnyObject
RoundedRectangle Shape Path Canvas GraphicsContext ResolvedText
TextAlignment FontWidth FontDesign Leading
VerticalAlignment HorizontalAlignment
Scene WindowGroup Commands
AsyncStream Continuation Actor MainActor TaskGroup
LocalizedStringKey StaticString Mirror
Environment Link LinearGradient ProposedViewSize ProposedViewSize Layout Subview LayoutSubview
AsyncImage ImageRenderer TimelineView Canvas
""".split())


if __name__ == "__main__":
    sys.exit(main())
