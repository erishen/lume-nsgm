// app.js — lume-nsgm SSR UI 增强（零依赖原生 JS，defer 加载）
(function () {
  "use strict";

  // 1) 删除确认：所有 a.del 链接点击前弹确认，取消则拦截
  document.addEventListener("click", function (e) {
    var a = e.target.closest ? e.target.closest("a.del") : null;
    if (a && !window.confirm("确认删除该记录？此操作不可恢复。")) {
      e.preventDefault();
    }
  });

  // 2) 表格排序：点击表头切换升/降序（数字感知、中文本地化比较）
  var tables = document.querySelectorAll("table.grid");
  for (var t = 0; t < tables.length; t++) {
    (function (table) {
      var ths = table.querySelectorAll("thead th");
      for (var i = 0; i < ths.length; i++) {
        (function (th, idx) {
          th.classList.add("sortable");
          th.title = "点击排序";
          th.addEventListener("click", function () {
            var tbody = table.querySelector("tbody");
            if (!tbody) { return; }
            var rows = [];
            var trs = tbody.querySelectorAll("tr");
            for (var r = 0; r < trs.length; r++) {
              if (!trs[r].querySelector("td[colspan]")) { rows.push(trs[r]); } // 跳过“暂无数据”占位行
            }
            var asc = th.getAttribute("data-sort") !== "asc";
            for (var k = 0; k < ths.length; k++) { ths[k].removeAttribute("data-sort"); }
            th.setAttribute("data-sort", asc ? "asc" : "desc");
            rows.sort(function (r1, r2) {
              var c1 = r1.children[idx], c2 = r2.children[idx];
              var v1 = c1 ? c1.textContent.trim() : "";
              var v2 = c2 ? c2.textContent.trim() : "";
              var n1 = parseFloat(v1), n2 = parseFloat(v2);
              var cmp;
              if (!isNaN(n1) && !isNaN(n2) && /^[\d.+-]/.test(v1) && /^[\d.+-]/.test(v2)) {
                cmp = n1 - n2;
              } else {
                cmp = v1.localeCompare(v2, "zh-CN");
              }
              return asc ? cmp : -cmp;
            });
            for (var w = 0; w < rows.length; w++) { tbody.appendChild(rows[w]); }
          });
        })(ths[i], i);
      }
    })(tables[t]);
  }

  // 3) 时间列格式化：td[data-ts]（SQLite CURRENT_TIMESTAMP 为 UTC "YYYY-MM-DD HH:MM:SS"）
  var tds = document.querySelectorAll("td[data-ts]");
  for (var d = 0; d < tds.length; d++) {
    (function (td) {
      var raw = td.getAttribute("data-ts") || "";
      var m = raw.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/);
      if (!m) { return; }
      var dt = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]));
      if (isNaN(dt.getTime())) { return; }
      var p2 = function (n) { return n < 10 ? "0" + n : "" + n; };
      td.textContent = dt.getFullYear() + "-" + p2(dt.getMonth() + 1) + "-" + p2(dt.getDate())
        + " " + p2(dt.getHours()) + ":" + p2(dt.getMinutes());
      td.title = raw + " (UTC)";
    })(tds[d]);
  }
})();
