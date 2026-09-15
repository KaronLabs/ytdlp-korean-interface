#include "gui.hpp"
#include <iterator>

namespace
{
    // CreateProcess argument quoting, including quotes and trailing backslashes.
    std::wstring quote_arg(const std::wstring& value)
    {
        std::wstring result {L"\""};
        size_t slashes = 0;
        for(auto c : value)
        {
            if(c == L'\\') { ++slashes; continue; }
            result.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
            slashes = 0;
            result += c;
        }
        result.append(slashes * 2, L'\\');
        return result + L'"';
    }

    fs::path quality_tool(const settings_t& settings, const wchar_t* name)
    {
        std::error_code ec;
        if(!settings.ffmpeg_path.empty())
        {
            auto directory {settings.ffmpeg_path};
            if(directory.has_extension() && directory.extension() == L".exe") directory = directory.parent_path();
            return fs::absolute(directory / name, ec);
        }
        for(const auto& directory : {settings.ytdlp_path.parent_path(), util::appdir()})
            if(fs::is_regular_file(directory / name, ec)) return fs::absolute(directory / name, ec);
        wchar_t path[32768] {};
        const auto size {SearchPathW(nullptr, name, nullptr, 32768, path, nullptr)};
        return size && size < 32768 ? fs::path(path) : fs::path{};
    }

    std::wstring quality_command(const settings_t& settings, const download_policy::policy& policy,
        const fs::path& folder, const fs::path& filename, const std::string& pinned = "")
    {
        std::wstring command {quote_arg(settings.ytdlp_path.wstring())};
        for(const auto& arg : download_policy::arguments(policy, pinned))
            command += L" " + quote_arg(nana::to_wstring(arg));
        command += L" --encoding UTF-8";
        const auto ffmpeg {quality_tool(settings, L"ffmpeg.exe")};
        if(!ffmpeg.empty()) command += L" --ffmpeg-location " + quote_arg(ffmpeg.parent_path().wstring());
        static const std::vector<std::wstring> browsers {L"", L"brave", L"chrome", L"chromium", L"edge",
            L"firefox", L"opera", L"safari", L"vivaldi", L"whale"};
        if(settings.com_cookies && settings.com_cookies < browsers.size())
            command += L" --cookies-from-browser " + quote_arg(browsers[settings.com_cookies] + nana::to_wstring(settings.cookie_options));
        else if(settings.cb_cookies && !settings.cookies_path.empty())
            command += L" --cookies " + quote_arg(settings.cookies_path.wstring());
        if(settings.cb_proxy) command += L" --proxy " + quote_arg(settings.proxy);
        if(!folder.empty()) command += L" -P " + quote_arg(folder.wstring());
        const auto output {filename.empty() ? settings.output_template : filename.filename().wstring() + L".%(ext)s"};
        if(!output.empty()) command += L" -o " + quote_arg(output);
        return command;
    }

    struct metadata_result
    {
        nlohmann::json data;
        std::string diagnostics;
        DWORD status = static_cast<DWORD>(-1);
    };

    metadata_result resolve_quality(const settings_t& settings, const download_policy::policy& policy,
        const fs::path& folder, const fs::path& filename, const std::wstring& url, std::atomic_bool& working)
    {
        metadata_result result;
        auto command {quality_command(settings, policy, folder, filename)};
        std::error_code ec;
        if((url.find(L"youtube.com") != std::wstring::npos || url.find(L"youtu.be") != std::wstring::npos) &&
            fs::exists(settings.ytdlp_path.parent_path() / "qjs.exe", ec))
            command += L" --js-runtimes quickjs";
        // Flat playlist inspection is deliberate: never resolve one entry for a whole list.
        command += L" --simulate --dump-single-json --flat-playlist -I 1 -- " + quote_arg(url);
        const auto output {util::run_piped_process(command, &working, nullptr, nullptr, nullptr, "", &result.status)};
        std::istringstream lines(output);
        std::string line;
        while(std::getline(lines, line))
        {
            if(!line.empty() && line.front() == '{')
            {
                auto data {nlohmann::json::parse(line, nullptr, false)};
                if(!data.is_discarded() && data.is_object()) { result.data = std::move(data); continue; }
            }
            if(!line.empty()) result.diagnostics += line + "\n";
        }
        return result;
    }

    std::string quality_error(const std::string& code)
    {
        if(code == "advanced_required") return i18n::tr("quality.boundary", "Playlist/live input uses Advanced mode. Basic quality presets do not apply.");
        if(code == "missing_audio") return i18n::tr("quality.error.audio", "The selected formats contain no confirmed audio stream.");
        if(code == "missing_video") return i18n::tr("quality.error.video", "The selected formats contain no confirmed video stream.");
        if(code == "unknown_dimensions") return i18n::tr("quality.error.dimensions", "The selected video dimensions are unknown. Choose Best available or Advanced explicitly.");
        if(code == "resolution_exceeds_cap") return i18n::tr("quality.error.cap", "No acceptable selection within the resolution limit. The selected video exceeds the limit.");
        if(code == "changed_selection") return i18n::tr("quality.error.changed", "Available resolution or audio changed since the preview. Paused: analyze again before downloading.");
        if(code == "ffmpeg") return i18n::tr("quality.error.ffmpeg", "FFmpeg is missing or cannot execute. Open Tools / settings and check the FFmpeg location or updater.");
        if(code == "ffprobe") return i18n::tr("quality.error.ffprobe", "ffprobe is missing or cannot execute. Open Tools / settings and check the FFmpeg tools.");
        if(code == "final_path") return i18n::tr("quality.error.path", "The final output path was not reported or is ambiguous. Any downloaded files are preserved.");
        if(code == "download") return i18n::tr("quality.error.download", "Download or postprocessing failed. Files are preserved; see output for the extractor error.");
        if(code == "output_mismatch") return i18n::tr("quality.error.output", "The final file does not match the selected video. It is preserved for inspection.");
        if(code == "probe") return i18n::tr("quality.error.probe", "The final file could not be inspected. It is preserved; see output.");
        if(code == "invalid_format_id") return i18n::tr("quality.error.id", "The selected format ID cannot be pinned safely. Use Advanced explicitly.");
        return i18n::tr("quality.error.metadata", "Stream metadata is missing or invalid. Analyze again or inspect the output in Advanced mode.") + " [" + code + "]";
    }

    std::string quality_dimensions(const download_policy::inspection& selected)
    {
        if(!selected.video) return i18n::tr("quality.audio_only", "audio only");
        if(!selected.dimensions_known) return i18n::tr("quality.unknown", "resolution unknown");
        return std::to_string(selected.width) + "x" + std::to_string(selected.height);
    }

    bool executable_tool(const fs::path& executable, const char* name, std::atomic_bool& working)
    {
        if(executable.empty()) return false;
        DWORD status {};
        auto result {util::run_piped_process(quote_arg(executable.wstring()) + L" -version",
            &working, nullptr, nullptr, nullptr, "", &status)};
        return working && status == 0 && result.find(std::string(name) + " version") != std::string::npos;
    }

    struct output_receipt
    {
        fs::path path;
        output_receipt()
        {
            wchar_t directory[MAX_PATH] {}, filename[MAX_PATH] {};
            auto size {GetTempPathW(MAX_PATH, directory)};
            if(size && size < MAX_PATH && GetTempFileNameW(directory, L"yqp", 0, filename)) path = filename;
        }
        ~output_receipt() { if(!path.empty()) { std::error_code ec; fs::remove(path, ec); } }
        fs::path final_path() const
        {
            std::ifstream input(path, std::ios::binary);
            std::string line;
            fs::path result;
            while(std::getline(input, line))
            {
                if(line.empty() || line == "\r") continue;
                const auto value {nlohmann::json::parse(line, nullptr, false)};
                if(!value.is_string() || !result.empty()) return {};
                result = fs::u8path(value.get<std::string>());
            }
            return result;
        }
    };
}

void GUI::gui_bottom::capture_policy_settings()
{
    const auto& source {GUI::conf};
    auto& target {policy_settings};
    target.ytdlp_path = source.ytdlp_path;
    target.ffmpeg_path = source.ffmpeg_path;
    target.output_template = source.output_template;
    target.com_cookies = source.com_cookies;
    target.cookie_options = source.cookie_options;
    target.cb_cookies = source.cb_cookies;
    target.cookies_path = source.cookies_path;
    target.cb_proxy = source.cb_proxy;
    target.proxy = source.proxy;
    target.sub_format = source.sub_format;
    target.sub_langs = source.sub_langs;
}

nlohmann::json GUI::gui_bottom::policy_to_json()
{
    std::lock_guard lock(policy_mutex);
    const auto& s {policy_settings};
    return {{"download_policy", download_policy::serialize(policy)}, {"policy_blocked", policy_blocked.load()},
        {"policy_item", {
            {"outpath", nana::to_utf8(outpath.wstring())}, {"outfile", nana::to_utf8(outfile.wstring())},
            {"rate", rate}, {"ratelim_unit", ratelim_unit}, {"sub_format", sub_format}, {"sub_langs", sub_langs},
            {"cbthumb", cbthumb}, {"cbsubs", cbsubs}, {"cbtime", cbtime}}},
        {"policy_context", {
            {"ytdlp_path", nana::to_utf8(s.ytdlp_path.wstring())}, {"ffmpeg_path", nana::to_utf8(s.ffmpeg_path.wstring())},
            {"output_template", nana::to_utf8(s.output_template)}, {"com_cookies", s.com_cookies},
            {"cookie_options", s.cookie_options}, {"cb_cookies", s.cb_cookies}, {"cookies_path", nana::to_utf8(s.cookies_path.wstring())},
            {"cb_proxy", s.cb_proxy}, {"proxy", nana::to_utf8(s.proxy)},
            {"sub_format", s.sub_format}, {"sub_langs", s.sub_langs}}}};
}

void GUI::gui_bottom::policy_from_json(const nlohmann::json& j)
{
    std::lock_guard lock(policy_mutex);
    policy = download_policy::deserialize(j.is_object() && j.contains("download_policy") ? j["download_policy"] : nlohmann::json{});
    policy_blocked = j.is_object() && j.contains("policy_blocked") && j["policy_blocked"] == true;
    if(j.is_object() && j.contains("policy_context"))
    {
        try
        {
            const auto& c {j.at("policy_context")};
            auto s {policy_settings};
            s.ytdlp_path = fs::u8path(c.at("ytdlp_path").get<std::string>());
            s.ffmpeg_path = fs::u8path(c.at("ffmpeg_path").get<std::string>());
            s.output_template = nana::to_wstring(c.at("output_template").get<std::string>());
            s.com_cookies = c.at("com_cookies").get<unsigned>();
            s.cookie_options = c.at("cookie_options").get<std::string>();
            s.cb_cookies = c.at("cb_cookies").get<bool>();
            s.cookies_path = fs::u8path(c.at("cookies_path").get<std::string>());
            s.cb_proxy = c.at("cb_proxy").get<bool>();
            s.proxy = nana::to_wstring(c.at("proxy").get<std::string>());
            s.sub_format = c.at("sub_format").get<std::string>();
            s.sub_langs = c.at("sub_langs").get<std::string>();
            policy_settings = std::move(s);
        }
        catch(const nlohmann::json::exception&) { policy = download_policy::deserialize(nullptr); }
    }
    if(j.is_object() && j.contains("policy_item"))
    {
        try
        {
            const auto& item {j.at("policy_item")};
            const auto folder {fs::u8path(item.at("outpath").get<std::string>())};
            const auto filename {fs::u8path(item.at("outfile").get<std::string>())};
            const auto saved_rate {item.at("rate").get<std::string>()};
            const auto saved_unit {item.at("ratelim_unit").get<unsigned>()};
            const auto saved_format {item.at("sub_format").get<std::string>()};
            const auto saved_langs {item.at("sub_langs").get<std::string>()};
            const auto thumb {item.at("cbthumb").get<bool>()}, subs {item.at("cbsubs").get<bool>()},
                time {item.at("cbtime").get<bool>()};
            outpath = folder;
            outfile = filename;
            rate = saved_rate;
            ratelim_unit = saved_unit;
            sub_format = saved_format;
            sub_langs = saved_langs;
            cbthumb = thumb;
            cbsubs = subs;
            cbtime = time;
        }
        catch(const nlohmann::json::exception&) { policy = download_policy::deserialize(nullptr); }
    }
    preview = {};
    policy_ui_dirty = true;
}

void GUI::set_quality_policy(download_policy::policy policy)
{
    auto& bottom {bottoms.current()};
    if(bottom.started) return;
    // Legacy info parsing is unchanged; wait for it before changing its interpretation.
    if(!bottom.policy_info_basic && (bottom.info_thread_active || bottom.info_thread.joinable())) return;
    {
        std::lock_guard lock(bottom.policy_mutex);
        ++bottom.policy_generation;
        bottom.policy_notice.clear();
        if(download_policy::is_basic(policy) && (bottom.is_playlist() || bottom.is_ytchan || bottom.is_bcchan ||
            bottom.is_yttab || bottom.live_scheduled || download_policy::detail::boundary(bottom.vidinfo)))
        {
            policy.mode_value = download_policy::mode::advanced;
            bottom.policy_notice = quality_error("advanced_required");
        }
        bottom.policy = policy;
        bottom.policy_start_pending = false;
        bottom.capture_policy_settings();
        bottom.preview = {};
        bottom.policy_blocked = false;
        if(download_policy::is_basic(policy)) bottom.use_strfmt = false;
        conf.download = policy;
        bottom.policy_refresh_pending = !bottom.url.empty();
    }
    quality_ui();
    save_queue = true;
}

void GUI::quality_ui()
{
    if(policy_showing || g_exiting) return;
    auto& bottom {bottoms.current()};
    std::lock_guard lock(bottom.policy_mutex);
    policy_showing = true;
    const auto basic {download_policy::is_basic(bottom.policy)};
    l_outpath.source_path(basic || !conf.common_dl_options ? &bottom.outpath : &conf.outpath);
    const auto active {bottom.started.load()};
    const auto info_busy {bottom.info_thread_active || bottom.info_thread.joinable()};
    com_mode.option(bottom.policy.mode_value == download_policy::mode::basic_video ? 0 :
        bottom.policy.mode_value == download_policy::mode::basic_audio ? 1 : 2);
    com_quality.option(bottom.policy.quality_value == download_policy::quality::p1080 ? 0 :
        bottom.policy.quality_value == download_policy::quality::p720 ? 1 : 2);
    com_mode.enabled(!active && ((basic && bottom.policy_info_basic) || !info_busy));
    com_quality.enabled(!active && bottom.policy.mode_value == download_policy::mode::basic_video && (!info_busy || bottom.policy_info_basic));
    btn_recommended.enable(!active && ((basic && bottom.policy_info_basic) || !info_busy));
    btn_analyze.enable(!active && !bottom.url.empty());
    btn_ytfmtlist.enable(!active && !info_busy && !bottom.vidinfo.empty());
    cbargs.enabled(!basic && !active);
    btncopy.enable(!basic && !active);
    com_args.enabled(!basic && !active);
    cbmp3.enabled(!basic && !active);
    cbkeyframes.enabled(!basic && !active);
    com_chap.enabled(!basic && !active);
    cbthumb.enabled(!active);
    cbsubs.enabled(!active);
    cbtime.enabled(!active);
    tbrate.enabled(!active);
    com_rate.enabled(!active);
    l_outpath.enabled(!active);
    btndl.enable(!bottom.url.empty() && (active || (!info_busy && !bottom.policy_refresh_pending &&
        (!basic || (bottom.preview.valid && !bottom.policy_blocked)))));
    if(active) btndl.caption(stop_download_label);
    else btndl.caption(start_download_label);
    std::string text;
    if(basic)
    {
        text = i18n::tr("quality.target", "Target: ") +
            (bottom.policy.mode_value == download_policy::mode::basic_audio ? std::string("MP3") :
                bottom.policy.quality_value == download_policy::quality::best ? i18n::tr("quality.best", "Best available") :
                bottom.policy.quality_value == download_policy::quality::p720 ? "720p" : "1080p");
        text += " | " + i18n::tr("quality.selected", "Selected: ") +
            (bottom.preview.valid ? quality_dimensions(bottom.preview) : i18n::tr("quality.pending", "analysis required"));
        text += " | " + i18n::tr("quality.audio_auto", "Audio: automatic") + " | " +
            i18n::tr("quality.container", "Container: automatic");
        if(bottom.preview.valid)
            text += bottom.preview.audio ? i18n::tr("quality.audio_present", " (audio present)") : i18n::tr("quality.audio_absent", " (audio absent)");
    }
    else text = i18n::tr("quality.advanced_hint", "Advanced: existing preferences, manual formats and custom arguments apply.");
    if(!bottom.policy_notice.empty()) text += "\n" + bottom.policy_notice;
    else if(basic) text += "\n" + i18n::tr("quality.available_hint", "Selection reflects currently available formats. External configuration and custom arguments are ignored.");
    l_quality.caption(text);
    l_quality.tooltip(text);
    policy_showing = false;
}

void GUI::quality_analyze(gui_bottom& bottom, std::uint64_t generation)
{
    download_policy::policy policy;
    settings_t settings;
    fs::path folder, filename;
    {
        std::lock_guard lock(bottom.policy_mutex);
        policy = bottom.policy;
        settings = bottom.policy_settings;
        folder = bottom.outpath;
        filename = bottom.outfile;
        bottom.policy_stage = i18n::tr("quality.stage.analyze", "Analyzing");
        bottom.policy_ui_dirty = true;
    }
    metadata_result result;
    download_policy::inspection selection;
    try
    {
        result = resolve_quality(settings, policy, folder, filename, bottom.url, bottom.working_info);
        selection = download_policy::inspect_selected(result.data, policy);
        if(result.status != 0 && !selection.boundary) { selection.valid = false; selection.error = "extractor"; }
        if(result.diagnostics.find("This live event will begin") != std::string::npos)
        { selection.valid = false; selection.boundary = true; selection.error = "advanced_required"; }
    }
    catch(const std::exception& e) { result.diagnostics = e.what(); selection.error = "invalid_metadata"; }
    if(!bottom.working_info || generation != bottom.policy_generation || g_exiting) return;
    {
        std::lock_guard lock(bottom.policy_mutex);
        if(generation != bottom.policy_generation) return;
        bottom.preview = selection;
        bottom.preview_generation = generation;
        bottom.vidinfo = std::move(result.data);
        bottom.media_title = download_policy::detail::string(bottom.vidinfo, "title");
        bottom.policy_stage.clear();
        bottom.policy_notice = selection.valid ? "" : quality_error(selection.error);
        if(!result.diagnostics.empty() && selection.valid)
            bottom.policy_notice = i18n::tr("quality.warnings", "Extractor warnings: see output; some formats may be unavailable.");
        bottom.policy_blocked = !selection.valid;
        bottom.policy_route_advanced = selection.boundary;
        bottom.policy_ui_dirty = true;
    }
    if(!result.diagnostics.empty()) outbox.append(bottom.url, result.diagnostics);
}

bool GUI::process_basic_item(gui_bottom& bottom)
{
    if(bottom.policy_download_active)
    {
        bottom.policy_stop_requested = true;
        bottom.policy_start_pending = false;
        if(!autostart_next_item || !conf.cb_autostart) bottom.policy_advance_after_cancel = false;
        bottom.working = false;
        return false;
    }
    if(bottom.started) return false;
    // Automatic dispatch filters stopped items; an explicit start can resume one.
    bottom.policy_stop_requested = false;
    if(bottom.info_thread_active || bottom.info_thread.joinable() || bottom.policy_refresh_pending)
    {
        bottom.policy_start_pending = true;
        return false;
    }
    download_policy::policy policy;
    download_policy::inspection preview;
    settings_t settings;
    fs::path folder, filename;
    {
        std::lock_guard lock(bottom.policy_mutex);
        if(!bottom.preview.valid || bottom.preview_generation != bottom.policy_generation || bottom.policy_blocked)
            return false;
        policy = bottom.policy;
        preview = bottom.preview;
        settings = bottom.policy_settings;
        folder = bottom.outpath;
        filename = bottom.outfile;
        settings.cbthumb = bottom.cbthumb;
        settings.cbsubs = bottom.cbsubs;
        settings.cbtime = bottom.cbtime;
        if(!bottom.sub_format.empty()) settings.sub_format = bottom.sub_format;
        if(!bottom.sub_langs.empty()) settings.sub_langs = bottom.sub_langs;
        settings.ratelim_unit = bottom.ratelim_unit;
        try { settings.ratelim = bottom.rate.empty() ? 0 : std::stod(bottom.rate); } catch(...) { settings.ratelim = 0; }
        bottom.policy_stage = i18n::tr("quality.stage.analyze", "Analyzing");
        bottom.policy_notice.clear();
        bottom.printed_path.clear();
        bottom.policy_success = false;
        bottom.policy_cancelled = false;
        bottom.policy_advance_after_cancel = true;
        bottom.policy_ui_dirty = true;
        bottom.started = true;
        bottom.working = true;
        bottom.policy_download_active = true;
        bottom.policy_download_finished = false;
    }
    const auto generation {bottom.policy_generation.load()};
    const auto url {bottom.url};
    auto item {lbq.item_from_value(url)};
    if(item != lbq.empty_item)
    {
        item.check(false);
        item.value<lbqval_t>().state = queue_item_state::active;
    }
    bottom.dl_thread = std::thread([this, &bottom, policy, preview, settings, folder, filename, generation, url]
    {
        std::string error;
        auto stage = [&](std::string value)
        {
            std::lock_guard lock(bottom.policy_mutex);
            bottom.policy_stage = std::move(value);
            bottom.policy_ui_dirty = true;
        };
        try
        {
            auto fresh {resolve_quality(settings, policy, folder, filename, url, bottom.working)};
            if(!fresh.diagnostics.empty()) outbox.append(url, fresh.diagnostics);
            auto selection {download_policy::inspect_selected(fresh.data, policy)};
            if(fresh.status != 0) error = "extractor";
            else if(!selection.valid) error = selection.error;
            else if(generation != bottom.policy_generation || !download_policy::same_selection(preview, selection))
                error = "changed_selection";
            const auto ffmpeg {quality_tool(settings, L"ffmpeg.exe")}, ffprobe {quality_tool(settings, L"ffprobe.exe")};
            const bool needs_ffmpeg {policy.mode_value == download_policy::mode::basic_audio ||
                selection.format_ids.find('+') != std::string::npos || settings.cbsubs || settings.cbthumb};
            if(error.empty() && bottom.working && needs_ffmpeg && !executable_tool(ffmpeg, "ffmpeg", bottom.working)) error = "ffmpeg";
            if(error.empty() && bottom.working && !executable_tool(ffprobe, "ffprobe", bottom.working)) error = "ffprobe";
            if(error.empty() && bottom.working)
            {
                output_receipt receipt;
                if(receipt.path.empty()) error = "final_path";
                else
                {
                    auto command {quality_command(settings, policy, folder, filename, selection.format_ids)};
                    std::error_code ec;
                    if((url.find(L"youtube.com") != std::wstring::npos || url.find(L"youtu.be") != std::wstring::npos) &&
                        fs::exists(settings.ytdlp_path.parent_path() / "qjs.exe", ec))
                        command += L" --js-runtimes quickjs";
                    if(settings.cbtime) command += L" --no-mtime";
                    if(settings.cbthumb) command += L" --embed-thumbnail";
                    if(settings.cbsubs)
                    {
                        command += L" --embed-subs";
                        if(!settings.sub_format.empty()) command += L" --sub-format " + quote_arg(nana::to_wstring(settings.sub_format));
                        if(!settings.sub_langs.empty()) command += L" --sub-langs " + quote_arg(nana::to_wstring(settings.sub_langs));
                    }
                    if(settings.ratelim > 0)
                        command += L" -r " + quote_arg(std::to_wstring(settings.ratelim) + (settings.ratelim_unit ? L"M" : L"K"));
                    command += L" --no-simulate --newline --progress --progress-delta .8 --print-to-file " +
                        quote_arg(L"after_move:%(filepath)j") + L" " + quote_arg(receipt.path.wstring()) + L" -- " + quote_arg(url);
                    // Persist the pinned IDs as evidence; never retry with a fallback selector.
                    {
                        std::lock_guard lock(bottom.policy_mutex);
                        bottom.policy_command = nana::to_utf8(command);
                        bottom.policy_ui_dirty = true;
                    }
                    outbox.append(url, i18n::tr("quality.pinned", "Pinned format IDs: ") + selection.format_ids + "\n");
                    stage(i18n::tr("quality.stage.download", "Downloading"));
                    auto append = [this, url, &stage](std::string text, bool keyword)
                    {
                        if(keyword) return;
                        if(text.find("[Merger]") != std::string::npos || text.find("[ExtractAudio]") != std::string::npos ||
                            text.find("[Fixup") != std::string::npos || text.find("[Embed") != std::string::npos)
                            stage(i18n::tr("quality.stage.postprocess", "Postprocessing"));
                        outbox.append(url, text);
                    };
                    auto progress = [&stage](ULONGLONG completed, ULONGLONG total, std::string text, int, int)
                    {
                        if(total == 1000)
                            stage(i18n::tr("quality.stage.download", "Downloading") + " " + std::to_string(completed / 10) + "%");
                        else if(text.find("[Merger]") == 0 || text.find("[ExtractAudio]") == 0 || text.find("[Fixup") == 0)
                            stage(i18n::tr("quality.stage.postprocess", "Postprocessing"));
                    };
                    DWORD status {};
                    util::run_piped_process(command, &bottom.working, append, progress, &bottom.graceful_exit, "", &status);
                    const auto final_path {receipt.final_path()};
                    {
                        std::lock_guard lock(bottom.policy_mutex);
                        bottom.printed_path = final_path;
                    }
                    if(status != 0) error = "download";
                    else if(bottom.working)
                    {
                        if(final_path.empty() || !fs::is_regular_file(final_path, ec)) error = "final_path";
                        else
                        {
                            stage(i18n::tr("quality.stage.inspect", "Inspecting file"));
                            DWORD probe_status {};
                            const auto output {util::run_piped_process(quote_arg(ffprobe.wstring()) +
                                L" -v error -show_streams -of json " + quote_arg(final_path.wstring()),
                                &bottom.working, nullptr, nullptr, nullptr, "", &probe_status)};
                            const auto metadata {nlohmann::json::parse(output, nullptr, false)};
                            const auto actual {download_policy::inspect_output(metadata, policy)};
                            if(probe_status != 0 || metadata.is_discarded()) { error = "probe"; outbox.append(url, output); }
                            else if(!actual.valid) error = actual.error;
                            else if(policy.mode_value == download_policy::mode::basic_video && selection.dimensions_known &&
                                ((std::min)(selection.width, selection.height) != (std::min)(actual.width, actual.height) ||
                                 (std::max)(selection.width, selection.height) != (std::max)(actual.width, actual.height)))
                                error = "output_mismatch";
                            if(error.empty() && bottom.working)
                                outbox.append(url, i18n::tr("quality.inspected", "Inspected final file: ") + nana::to_utf8(final_path.wstring()) + "\n");
                        }
                    }
                }
            }
        }
        catch(const std::exception& e) { error = "download"; outbox.append(url, std::string(e.what()) + "\n"); }
        {
            std::lock_guard lock(bottom.policy_mutex);
            bottom.policy_cancelled = !bottom.working;
            bottom.policy_success = error.empty() && bottom.working;
            bottom.policy_blocked = !bottom.policy_success && !bottom.policy_cancelled;
            bottom.policy_stage = bottom.policy_cancelled ? i18n::tr("queue.status.stopped", "stopped") :
                bottom.policy_success ? i18n::tr("quality.stage.done", "Done (file inspected)") : i18n::tr("quality.stage.paused", "Paused");
            bottom.policy_notice = error.empty() ? "" : quality_error(error);
            if(!bottom.policy_success && !bottom.policy_cancelled)
                bottom.policy_notice += " " + i18n::tr("quality.preserved", "Files are preserved. No automatic redownload.");
            bottom.policy_ui_dirty = true;
        }
        if(!error.empty() && bottom.working) outbox.append(url, quality_error(error) + "\n");
        bottom.policy_download_finished = true;
    });
    quality_ui();
    return true;
}

void GUI::quality_tick()
{
    if(g_exiting || thr_queue_remove.joinable()) return;
    std::vector<std::wstring> refresh, finished, starts;
    for(auto& entry : bottoms)
    {
        auto& bottom {*entry.second};
        if(bottom.url.empty()) continue;
        auto row {lbq.item_from_value(bottom.url)};
        if(row == lbq.empty_item || row.checked() || row.value<lbqval_t>().state == queue_item_state::skipped ||
            bottom.policy_stop_requested)
            bottom.policy_start_pending = false;
        if(bottom.policy_info_finished.exchange(false))
        {
            if(bottom.info_thread.joinable()) bottom.info_thread.join();
            save_queue = true;
            if(total_info_threads == 0)
            {
                items_initialized = true;
                lbq.auto_draw(true);
            }
        }
        if(bottom.policy_download_finished.exchange(false))
        {
            if(bottom.dl_thread.joinable()) bottom.dl_thread.join();
            bottom.started = false;
            bottom.working = false;
            bottom.policy_download_active = false;
            auto item {lbq.item_from_value(bottom.url)};
            if(item != lbq.empty_item)
                item.value<lbqval_t>().state = bottom.policy_success ? queue_item_state::done :
                    bottom.policy_cancelled ? queue_item_state::stopped : queue_item_state::error;
            finished.push_back(bottom.url);
            save_queue = true;
        }
        if(!bottom.started && !bottom.info_thread_active && !bottom.info_thread.joinable())
        {
            if(bottom.policy_route_advanced.exchange(false))
            {
                bottom.policy.mode_value = download_policy::mode::advanced;
                bottom.policy_refresh_pending = true;
            }
            if(bottom.policy_refresh_pending.exchange(false)) refresh.push_back(bottom.url);
            else if(bottom.policy_start_pending && download_policy::is_basic(bottom.policy))
            {
                if(bottom.policy_blocked) bottom.policy_start_pending = false;
                else if(bottom.preview.valid) starts.push_back(bottom.url);
            }
        }
        if(bottom.policy_ui_dirty.exchange(false))
        {
            std::lock_guard lock(bottom.policy_mutex);
            if(!bottom.policy_command.empty())
            {
                // This timer runs on the GUI owner of Outbox::commands.
                outbox.commands[bottom.url] = std::move(bottom.policy_command);
                bottom.policy_command.clear();
            }
            auto item {lbq.item_from_value(bottom.url)};
            if(item != lbq.empty_item)
            {
                if(download_policy::is_basic(bottom.policy) && !bottom.policy_download_active && bottom.preview.valid)
                {
                    item.text(2, bottom.media_title);
                    item.text(4, bottom.preview.format_ids);
                    item.text(5, quality_dimensions(bottom.preview));
                    item.text(6, i18n::tr("quality.auto", "automatic"));
                }
                if(item.checked() || item.value<lbqval_t>().state == queue_item_state::skipped)
                    item.text(3, i18n::tr("queue.status.skipped", "skip"));
                else if(!bottom.policy_stage.empty()) item.text(3, bottom.policy_stage);
                else if(bottom.policy_blocked)
                {
                    item.text(3, i18n::tr("quality.stage.paused", "Paused"));
                    item.value<lbqval_t>().state = queue_item_state::error;
                }
                else if(download_policy::is_basic(bottom.policy)) item.text(3, i18n::tr("queue.status.queued", "queued"));
                if(qurl == bottom.url && !bottom.policy_stage.empty()) prog.caption(bottom.policy_stage);
            }
        }
    }
    for(const auto& url : refresh) add_url(url, true);
    for(const auto& url : starts)
    {
        auto& bottom {bottoms.at(url)};
        auto row {lbq.item_from_value(url)};
        if(!bottom.policy_start_pending || bottom.policy_stop_requested || row == lbq.empty_item ||
            row.checked() || row.value<lbqval_t>().state == queue_item_state::skipped)
        {
            bottom.policy_start_pending = false;
            continue;
        }
        const auto active {std::count_if(bottoms.begin(), bottoms.end(), [](const auto& entry) { return entry.second->started.load(); })};
        if(active >= conf.max_concurrent_downloads) break;
        bottoms.at(url).policy_start_pending = false;
        if(process_basic_item(bottoms.at(url))) start_next_urls(url);
    }
    quality_ui();
    for(const auto& url : finished)
    {
        const auto& bottom {bottoms.at(url)};
        if(!bottom.policy_cancelled || bottom.policy_advance_after_cancel)
            start_next_urls(url);
    }
    if(!finished.empty()) queue_completion_pending = true;
    if(queue_completion_pending.exchange(false))
    {
        taskbar_overall_progress();
        queue_completion_actions();
    }
}

void GUI::queue_completion_actions()
{
    // Both basic and Advanced completions reach this GUI-owned gate.
    if(g_exiting || !lbq.item_count()) return;
    for(const auto& entry : bottoms)
        if(entry.second->started || entry.second->policy_download_active || entry.second->policy_start_pending)
            return;
    for(size_t category = 0; category < lbq.size_categ(); ++category)
        for(auto item : lbq.at(category))
            if(item.value<lbqval_t>().state != queue_item_state::done && item.value<lbqval_t>().state != queue_item_state::skipped)
                return;
    if(pwr_shutdown || pwr_hibernate || pwr_sleep) start_suspend_fm = true;
    if(close_when_finished) close();
}
