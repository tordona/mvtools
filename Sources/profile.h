// Portable, thread-safe micro-profiler for MVTools
// Uses Windows QueryPerformanceCounter (QPC) across x64 (TSC) and ARM64 (CNTVCT_EL0)

#ifndef __MV_profile__
#define __MV_profile__

#define MOTION_PROFILE_ME              0
#define MOTION_PROFILE_LUMA_VAR        1
#define MOTION_PROFILE_COMPENSATION    2
#define MOTION_PROFILE_INTERPOLATION   3
#define MOTION_PROFILE_PREDICTION      4
#define MOTION_PROFILE_2X              5
#define MOTION_PROFILE_MASK            6
#define MOTION_PROFILE_RESIZE          7
#define MOTION_PROFILE_FLOWINTER       8
#define MOTION_PROFILE_YUY2CONVERT     9
#define MOTION_PROFILE_GPU_SEARCH     10
#define MOTION_PROFILE_GPU_SYNTH      11
#define MOTION_PROFILE_COUNT          12

#define MOTION_PROFILE

#ifdef MOTION_PROFILE

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <profileapi.h>
#include <cstdint>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

namespace mvtools_prof
{
    struct StageStats
    {
        std::atomic<int64_t> total_ticks{0};
        std::atomic<int64_t> call_count{0};
    };

    inline StageStats g_stages[MOTION_PROFILE_COUNT];
    inline std::atomic<int> g_instance_count{0};
    inline std::atomic<int64_t> g_frame_counter{0};
    inline std::mutex g_report_mutex;

    inline bool is_enabled()
    {
        static int enabled = -1;
        if (enabled == -1)
        {
            const char* env = std::getenv("MVTOOLS_PROFILE");
            enabled = (env && (std::strcmp(env, "1") == 0 || std::strcmp(env, "true") == 0 || std::strcmp(env, "TRUE") == 0)) ? 1 : 0;
        }
        return enabled == 1;
    }

    inline int64_t get_frequency()
    {
        static int64_t freq = 0;
        if (freq == 0)
        {
            LARGE_INTEGER li;
            QueryPerformanceFrequency(&li);
            freq = li.QuadPart;
        }
        return freq;
    }

    inline int64_t get_ticks()
    {
        LARGE_INTEGER li;
        QueryPerformanceCounter(&li);
        return li.QuadPart;
    }

    inline thread_local int64_t t_start_ticks[MOTION_PROFILE_COUNT] = {0};

    inline void start(int stage)
    {
        if (!is_enabled() || stage < 0 || stage >= MOTION_PROFILE_COUNT) return;
        t_start_ticks[stage] = get_ticks();
    }

    inline void stop(int stage)
    {
        if (!is_enabled() || stage < 0 || stage >= MOTION_PROFILE_COUNT) return;
        int64_t end = get_ticks();
        int64_t start_val = t_start_ticks[stage];
        if (start_val > 0)
        {
            int64_t elapsed = end - start_val;
            g_stages[stage].total_ticks.fetch_add(elapsed, std::memory_order_relaxed);
            g_stages[stage].call_count.fetch_add(1, std::memory_order_relaxed);
            t_start_ticks[stage] = 0;
        }
    }

    inline void init()
    {
        if (!is_enabled()) return;
        g_instance_count.fetch_add(1, std::memory_order_relaxed);
    }

    inline std::string resolve_csv_path()
    {
        const char* csv_env = std::getenv("MVTOOLS_PROFILE_CSV");
        if (csv_env && csv_env[0] != '\0')
        {
            return std::string(csv_env);
        }

        // Safe fallback paths if not explicitly specified
        const char* program_data = std::getenv("ProgramData");
        if (program_data && program_data[0] != '\0')
        {
            return std::string(program_data) + "\\mvtools_profile.csv";
        }

        const char* temp_dir = std::getenv("TEMP");
        if (temp_dir && temp_dir[0] != '\0')
        {
            return std::string(temp_dir) + "\\mvtools_profile.csv";
        }

        return "mvtools_profile.csv";
    }

    inline void dump_report(bool print_console = true)
    {
        if (!is_enabled()) return;

        std::lock_guard<std::mutex> lock(g_report_mutex);

        int64_t freq = get_frequency();
        if (freq <= 0) return;

        static const char* stage_names[MOTION_PROFILE_COUNT] = {
            "Motion Estimation (ME) ",
            "Luma & Variance (VAR)   ",
            "Compensation (COMP)    ",
            "Interpolation (INTERP) ",
            "Prediction (PREDICT)   ",
            "Subpixel Finest (2X)   ",
            "Mask Generation (MASK) ",
            "Upsize / Resize (RESIZE)",
            "Flow Warping (FLOWINTER)",
            "Color Space (YUY2CONV) ",
            "D3D12 GPU Motion Search",
            "D3D12 GPU Flow Synth   "
        };

        int64_t total_profiled_ticks = 0;
        for (int i = 0; i < MOTION_PROFILE_COUNT; ++i)
        {
            total_profiled_ticks += g_stages[i].total_ticks.load(std::memory_order_relaxed);
        }

        if (total_profiled_ticks == 0) return;

        double total_ms = (double)total_profiled_ticks * 1000.0 / (double)freq;

        if (print_console)
        {
            char buf[2048];
            int pos = 0;
            pos += snprintf(buf + pos, sizeof(buf) - pos,
                "\n[MVTools Profiler] =========================================================================\n"
                "[MVTools Profiler] Stage Name               Total Time (ms)     Calls     Avg/Call    %% Total\n"
                "[MVTools Profiler] -------------------------------------------------------------------------\n");

            for (int i = 0; i < MOTION_PROFILE_COUNT; ++i)
            {
                int64_t ticks = g_stages[i].total_ticks.load(std::memory_order_relaxed);
                int64_t calls = g_stages[i].call_count.load(std::memory_order_relaxed);
                if (calls == 0 && ticks == 0) continue;

                double ms = (double)ticks * 1000.0 / (double)freq;
                double avg_us = calls > 0 ? (ms * 1000.0 / (double)calls) : 0.0;
                double pct = total_ms > 0 ? (ms * 100.0 / total_ms) : 0.0;

                pos += snprintf(buf + pos, sizeof(buf) - pos,
                    "[MVTools Profiler] %-24s %12.2f ms  %8lld  %8.1f us    %5.1f%%\n",
                    stage_names[i], ms, (long long)calls, avg_us, pct);
            }

            pos += snprintf(buf + pos, sizeof(buf) - pos,
                "[MVTools Profiler] -------------------------------------------------------------------------\n"
                "[MVTools Profiler] TOTAL PROFILED TIME:     %12.2f ms\n"
                "[MVTools Profiler] =========================================================================\n\n",
                total_ms);

            fputs(buf, stderr);
            fflush(stderr);
            OutputDebugStringA(buf);
        }

        std::string csv_path = resolve_csv_path();
        if (!csv_path.empty())
        {
            FILE* fp = fopen(csv_path.c_str(), "w");
            if (fp)
            {
                fprintf(fp, "Stage,TotalTimeMs,Calls,AvgTimeUs,PctTotal\n");
                for (int i = 0; i < MOTION_PROFILE_COUNT; ++i)
                {
                    int64_t ticks = g_stages[i].total_ticks.load(std::memory_order_relaxed);
                    int64_t calls = g_stages[i].call_count.load(std::memory_order_relaxed);
                    if (calls == 0 && ticks == 0) continue;
                    double ms = (double)ticks * 1000.0 / (double)freq;
                    double avg_us = calls > 0 ? (ms * 1000.0 / (double)calls) : 0.0;
                    double pct = total_ms > 0 ? (ms * 100.0 / total_ms) : 0.0;
                    fprintf(fp, "\"%s\",%.3f,%lld,%.2f,%.2f\n",
                        stage_names[i], ms, (long long)calls, avg_us, pct);
                }
                fprintf(fp, "\"TOTAL\",%.3f,,,\n", total_ms);
                fflush(fp);
                fclose(fp);
            }
        }
    }

    // Called on every frame inside MVSuper::GetFrame
    inline void on_frame()
    {
        if (!is_enabled()) return;
        int64_t frame = g_frame_counter.fetch_add(1, std::memory_order_relaxed) + 1;
        // Periodic snapshot: Flush CSV every 48 frames (approx. every 2 seconds of 24 fps video)
        // so data is preserved even if the host process is forcefully terminated
        if (frame % 48 == 0)
        {
            dump_report(false);
        }
    }

    inline void show()
    {
        if (!is_enabled()) return;
        int remaining = g_instance_count.fetch_sub(1, std::memory_order_relaxed) - 1;
        if (remaining <= 0)
        {
            dump_report(true);
        }
    }
}

#define PROFILE_START(x)    mvtools_prof::start(x)
#define PROFILE_STOP(x)     mvtools_prof::stop(x)
#define PROFILE_INIT()      mvtools_prof::init()
#define PROFILE_CUMULATE()  mvtools_prof::on_frame()
#define PROFILE_SHOW()      mvtools_prof::show()

#else // !MOTION_PROFILE

#define PROFILE_START(x)
#define PROFILE_STOP(x)
#define PROFILE_INIT()
#define PROFILE_CUMULATE()
#define PROFILE_SHOW()

#endif // MOTION_PROFILE

#endif // __MV_profile__
