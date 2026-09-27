DAY = 86400

def _fmt2(x):
    neg = x < 0
    mag = -x if neg else x
    scaled = int(mag * 100 + 0.5)
    whole = scaled // 100
    frac = scaled - whole * 100
    frac_s = str(frac)
    if len(frac_s) < 2:
        frac_s = "0" + frac_s
    s = str(whole) + "." + frac_s
    if neg and scaled != 0:
        s = "-" + s
    return s

def _fetch_values(ctx, ts_id, days):
    end_unix = ctx.now.unix
    start_unix = end_unix - days * DAY

    end_s = _unix_to_iso(end_unix) + "Z"
    start_s = _unix_to_iso(start_unix) + "Z"

    url = "https://nhdes.rtiamanzi.org/api/timeseries/" + ts_id + "/values/"
    resp = http.get(url, params={"start": start_s, "end": end_s}, ttl_seconds=1800)

    if resp["status_code"] != 200:
        return None
    return resp["json"]

def _unix_to_iso(u):
    days = u // DAY
    secs = u % DAY
    y, m, d = _civil_from_days(days)
    hh = secs // 3600
    mm = (secs % 3600) // 60
    ss = secs % 60
    return (fmt.pad(y, width=4) + "-" + fmt.pad(m) + "-" + fmt.pad(d) +
            "T" + fmt.pad(hh) + ":" + fmt.pad(mm) + ":" + fmt.pad(ss))

def _civil_from_days(z):
    z = z + 719468
    era = (z if z >= 0 else z - 146096) // 146097
    doe = z - era * 146097
    yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    y = yoe + era * 400
    doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp = (5 * doy + 2) // 153
    d = doy - (153 * mp + 2) // 5 + 1
    m = mp + 3 if mp < 10 else mp - 9
    y = y + 1 if m <= 2 else y
    return y, m, d

def _latest_reading(records):
    if not records:
        return None
    best = records[0]
    for r in records:
        if r["datetime"] > best["datetime"]:
            best = r
    return best

def level(c, ctx):
    c.clear()
    ts_id = ctx.inputs.get("timeseriesid", "")
    normalpool = float(ctx.inputs.get("normalpool", 250.4))

    if not ts_id or ts_id == "PASTE-REAL-UUID-HERE":
        c.text_center("SET TIMESERIES ID", 12, font="5x7", color="red")
        return

    records = _fetch_values(ctx, ts_id, 2)
    if records == None:
        c.text_center("NO DATA", 12, font="6x8", color="red")
        return

    latest = _latest_reading(records)
    if latest == None:
        c.text_center("NO READINGS", 12, font="6x8", color="red")
        return

    elevation = latest["num_value"]
    drawdown = normalpool - elevation

    c.header("PAWTUCKAWAY LAKE", bg="skyblue", color="black")

    if drawdown > 0.005:
        label = _fmt2(drawdown) + " FT BELOW FULL"
        col = "amber"
    elif drawdown < -0.005:
        label = _fmt2(-drawdown) + " FT ABOVE FULL"
        col = "cyan"
    else:
        label = "AT FULL POOL"
        col = "green"

    c.text(_fmt2(elevation) + " FT ELEV", 4, 13, font="6x8", color="white")
    c.text_center(label, 25, font="4x5", color=col)

def trend(c, ctx):
    c.clear()
    ts_id = ctx.inputs.get("timeseriesid", "")
    normalpool = float(ctx.inputs.get("normalpool", 250.4))

    if not ts_id or ts_id == "PASTE-REAL-UUID-HERE":
        c.text_center("SET TIMESERIES ID", 12, font="5x7", color="red")
        return

    records = _fetch_values(ctx, ts_id, 7)
    if records == None or len(records) == 0:
        c.text_center("NO DATA", 14, font="6x8", color="red")
        return

    sorted_records = sorted(records, key=lambda r: r["datetime"])

    elevations = [r["num_value"] for r in sorted_records]

    current_elev = elevations[-1]
    current_dd = normalpool - current_elev

    target_unix = ctx.now.unix - DAY
    target_iso = _unix_to_iso(target_unix) + "Z"

    day_ago_elev = elevations[0]
    for i in range(len(sorted_records)):
        if sorted_records[i]["datetime"] >= target_iso:
            day_ago_elev = elevations[i]
            break

    diff = current_elev - day_ago_elev

    if diff > 0.01:
        arrow_dir = 1
        trend_col = "green"
    elif diff < -0.01:
        arrow_dir = -1
        trend_col = "red"
    else:
        arrow_dir = 0
        trend_col = "gray"

    axis_max = max(elevations)
    axis_min = min(elevations)
    swing = axis_max - axis_min
    if swing < 0.01:
        axis_max = axis_max + 0.05
        axis_min = axis_min - 0.05
        swing = axis_max - axis_min

    c.text("7-DAY LEVEL", 2, 1, font="4x5", color="gray")

    chart_x = 2
    chart_y = 8
    chart_w = 150
    chart_h = 14

    c.sparkline(elevations, chart_x, chart_y, chart_w, chart_h, color="skyblue",
                fill=color.dim("skyblue", 30), min_val=axis_min, max_val=axis_max)
    c.trend_arrow(154, 10, arrow_dir, color=trend_col)

    c.text("SWING " + _fmt2(swing), 2, 24, font="4x5", color=trend_col)
    c.text_right("DD " + _fmt2(current_dd), 27, font="4x5", color="white")