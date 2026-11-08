#if defined(_WIN32)
    #ifndef WIN32_LEAN_AND_MEAN
        #define WIN32_LEAN_AND_MEAN
    #endif
    #include <windows.h>
    #define GD_EXPORT __declspec(dllexport)
#else
    #define GD_EXPORT __attribute__((visibility("default")))
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gdextension_interface.h"
#include <fluidsynth.h>

// --- Global Interface Function Pointers ---
static GDExtensionInterfaceGetProcAddress g_get_proc_address = NULL;
static GDExtensionClassLibraryPtr g_library = NULL;

static GDExtensionInterfaceStringNameNewWithUtf8Chars g_string_name_new_with_utf8_chars = NULL;
static GDExtensionInterfaceStringNewWithUtf8Chars g_string_new_with_utf8_chars = NULL;
static GDExtensionInterfaceStringToUtf8Chars g_string_to_utf8_chars = NULL;
static GDExtensionInterfaceVariantDestroy g_variant_destroy = NULL;

static GDExtensionInterfaceGetVariantToTypeConstructor g_get_variant_to_type_constructor = NULL;
static GDExtensionInterfaceGetVariantFromTypeConstructor g_get_variant_from_type_constructor = NULL;

static GDExtensionTypeFromVariantConstructorFunc g_to_int = NULL;
static GDExtensionTypeFromVariantConstructorFunc g_to_float = NULL;
static GDExtensionTypeFromVariantConstructorFunc g_to_bool = NULL;
static GDExtensionTypeFromVariantConstructorFunc g_to_string = NULL;

static GDExtensionVariantFromTypeConstructorFunc g_from_int = NULL;
static GDExtensionVariantFromTypeConstructorFunc g_from_float = NULL;
static GDExtensionVariantFromTypeConstructorFunc g_from_bool = NULL;
static GDExtensionVariantFromTypeConstructorFunc g_from_pv2 = NULL;

static GDExtensionInterfaceClassdbConstructObject3 g_classdb_construct_object3 = NULL;
static GDExtensionInterfaceClassdbConstructObject g_classdb_construct_object = NULL;
static GDExtensionInterfaceObjectSetInstance g_object_set_instance = NULL;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 g_classdb_register_extension_class6 = NULL;
static GDExtensionInterfaceClassdbRegisterExtensionClass3 g_classdb_register_extension_class3 = NULL;
static GDExtensionInterfaceClassdbRegisterExtensionClass2 g_classdb_register_extension_class2 = NULL;
static GDExtensionInterfaceClassdbRegisterExtensionClass g_classdb_register_extension_class = NULL;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod g_classdb_register_extension_class_method = NULL;

static GDExtensionInterfacePackedVector2ArrayOperatorIndex g_packed_vector2_array_operator_index = NULL;
static GDExtensionPtrConstructor g_pv2_ctor = NULL;
static GDExtensionPtrDestructor g_pv2_dtor = NULL;
static GDExtensionPtrBuiltInMethod g_pv2_resize = NULL;

// --- Static StringNames ---
static char g_strname_ref_counted_buf[32];
static char g_strname_engine_buf[32];
static char g_strname_empty_buf[32];
static char g_str_empty_buf[32];

#define SNAME(buf) ((GDExtensionStringNamePtr)(buf))
#define SNAME_CONST(buf) ((GDExtensionConstStringNamePtr)(buf))
#define STR(buf) ((GDExtensionStringPtr)(buf))

// --- Engine Instance Struct ---
typedef struct {
    GDExtensionObjectPtr godot_obj;
    fluid_settings_t *settings;
    fluid_synth_t *synth;
    int sf_id;
    bool is_active;
} FluidSynthEngine;

static void engine_cleanup(FluidSynthEngine *engine) {
    if (!engine) return;
    if (engine->synth) {
        delete_fluid_synth(engine->synth);
        engine->synth = NULL;
    }
    if (engine->settings) {
        delete_fluid_settings(engine->settings);
        engine->settings = NULL;
    }
    engine->sf_id = -1;
    engine->is_active = false;
}

// --- Lifecycle Callbacks ---
static GDExtensionObjectPtr fluidsynth_create_instance(void *p_class_userdata, GDExtensionBool p_notify_postinitialize) {
    GDExtensionObjectPtr godot_obj = NULL;
    if (g_classdb_construct_object3) {
        godot_obj = g_classdb_construct_object3(SNAME_CONST(g_strname_ref_counted_buf));
    } else if (g_classdb_construct_object) {
        godot_obj = g_classdb_construct_object(SNAME_CONST(g_strname_ref_counted_buf));
    }
    if (!godot_obj) {
        return NULL;
    }

    FluidSynthEngine *engine = (FluidSynthEngine *)calloc(1, sizeof(FluidSynthEngine));
    engine->godot_obj = godot_obj;
    engine->sf_id = -1;
    engine->is_active = false;

    g_object_set_instance(godot_obj, SNAME_CONST(g_strname_engine_buf), (GDExtensionClassInstancePtr)engine);
    return godot_obj;
}

static void fluidsynth_free_instance(void *p_class_userdata, GDExtensionClassInstancePtr p_instance) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine) {
        engine_cleanup(engine);
        free(engine);
    }
}

// --- Helper to extract string from Variant ---
static void variant_get_cstring(GDExtensionConstVariantPtr var_ptr, char *out_buf, size_t max_buf) {
    out_buf[0] = '\0';
    if (!var_ptr || !g_to_string || !g_string_to_utf8_chars) return;
    char str_storage[32] = {0};
    g_to_string(str_storage, (GDExtensionVariantPtr)var_ptr);
    GDExtensionInt len = g_string_to_utf8_chars((GDExtensionConstStringPtr)str_storage, out_buf, (GDExtensionInt)(max_buf - 1));
    if (len >= 0 && (size_t)len < max_buf) {
        out_buf[len] = '\0';
    } else if ((size_t)len >= max_buf) {
        out_buf[max_buf - 1] = '\0';
    }
}

// --- Method 1: init_synth(gain: float = 1.0) -> bool ---
static void call_init_synth(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (!engine) return;

    engine_cleanup(engine);

    double gain = 1.0;
    if (p_argument_count > 0 && p_args[0]) {
        g_to_float(&gain, (GDExtensionVariantPtr)p_args[0]);
    }

    engine->settings = new_fluid_settings();
    if (!engine->settings) {
        uint8_t res = 0;
        if (r_return) g_from_bool(r_return, &res);
        return;
    }

    // MuseScore configurations + Dynamic Sample Loading (prevents OOM, loads in ~3s)
    fluid_settings_setint(engine->settings, "synth.dynamic-sample-loading", 1);
    fluid_settings_setnum(engine->settings, "synth.sample-rate", 44100.0);
    fluid_settings_setint(engine->settings, "synth.polyphony", 256);
    fluid_settings_setnum(engine->settings, "synth.gain", gain > 0.0 ? gain : 1.0);

    engine->synth = new_fluid_synth(engine->settings);
    if (!engine->synth) {
        delete_fluid_settings(engine->settings);
        engine->settings = NULL;
        uint8_t res = 0;
        if (r_return) g_from_bool(r_return, &res);
        return;
    }

    // MuseScore SoundFont default reverb
    fluid_synth_reverb_on(engine->synth, -1, 1);
    fluid_synth_set_reverb_group_roomsize(engine->synth, -1, 0.61);
    fluid_synth_set_reverb_group_damp(engine->synth, -1, 0.23);
    fluid_synth_set_reverb_group_width(engine->synth, -1, 0.76);
    fluid_synth_set_reverb_group_level(engine->synth, -1, 0.61);

    // Real-time cubic interpolation (4th-order b-spline, identical to MuseScore real-time playback)
    fluid_synth_set_interp_method(engine->synth, -1, FLUID_INTERP_4THORDER);

    engine->is_active = true;
    uint8_t res = 1;
    if (r_return) g_from_bool(r_return, &res);
}

// --- Method 2: render_frames(count: int) -> PackedVector2Array ---
static void call_render_frames(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    int64_t count = 0;
    if (p_argument_count > 0 && p_args[0]) {
        g_to_int(&count, (GDExtensionVariantPtr)p_args[0]);
    }
    if (count <= 0) count = 0;

    char pv2_storage[16] = {0};
    if (g_pv2_ctor) {
        g_pv2_ctor(pv2_storage, NULL);
    }

    if (count > 0 && g_pv2_resize && g_packed_vector2_array_operator_index) {
        GDExtensionConstTypePtr resize_args[1] = { &count };
        int64_t ret_code = 0;
        g_pv2_resize(pv2_storage, resize_args, &ret_code, 1);

        if (engine && engine->synth) {
            float *out_data = (float *)g_packed_vector2_array_operator_index(pv2_storage, 0);
            if (out_data) {
                // Interleaved stereo: left at offset 0 step 2, right at offset 1 step 2
                fluid_synth_write_float(engine->synth, (int)count,
                                        out_data, 0, 2,
                                        out_data, 1, 2);
            }
        }
    }

    if (r_return && g_from_pv2) {
        g_from_pv2(r_return, pv2_storage);
    }

    if (g_pv2_dtor) {
        g_pv2_dtor(pv2_storage);
    }
}

// --- Method 3: load_soundfont(path: String) -> int ---
static void call_load_soundfont(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    int64_t sfid = -1;

    if (engine && engine->synth && p_argument_count > 0 && p_args[0]) {
        char path[1024];
        variant_get_cstring(p_args[0], path, sizeof(path));
        if (strlen(path) > 0) {
            int res = fluid_synth_sfload(engine->synth, path, 1);
            engine->sf_id = res;
            sfid = res;
        }
    }

    if (r_return) g_from_int(r_return, &sfid);
}

// --- Method 4: note_on(channel: int, key: int, velocity: int) -> void ---
static void call_note_on(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine && engine->synth && p_argument_count >= 3) {
        int64_t chan = 0, key = 0, vel = 0;
        g_to_int(&chan, (GDExtensionVariantPtr)p_args[0]);
        g_to_int(&key, (GDExtensionVariantPtr)p_args[1]);
        g_to_int(&vel, (GDExtensionVariantPtr)p_args[2]);
        fluid_synth_noteon(engine->synth, (int)chan, (int)key, (int)vel);
    }
}

// --- Method 5: note_off(channel: int, key: int) -> void ---
static void call_note_off(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine && engine->synth && p_argument_count >= 2) {
        int64_t chan = 0, key = 0;
        g_to_int(&chan, (GDExtensionVariantPtr)p_args[0]);
        g_to_int(&key, (GDExtensionVariantPtr)p_args[1]);
        fluid_synth_noteoff(engine->synth, (int)chan, (int)key);
    }
}

// --- Method 6: pitch_bend(channel: int, value: int) -> void ---
static void call_pitch_bend(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine && engine->synth && p_argument_count >= 2) {
        int64_t chan = 0, val = 0;
        g_to_int(&chan, (GDExtensionVariantPtr)p_args[0]);
        g_to_int(&val, (GDExtensionVariantPtr)p_args[1]);
        fluid_synth_pitch_bend(engine->synth, (int)chan, (int)val);
    }
}

// --- Method 7: control_change(channel: int, controller: int, value: int) -> void ---
static void call_control_change(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine && engine->synth && p_argument_count >= 3) {
        int64_t chan = 0, ctrl = 0, val = 0;
        g_to_int(&chan, (GDExtensionVariantPtr)p_args[0]);
        g_to_int(&ctrl, (GDExtensionVariantPtr)p_args[1]);
        g_to_int(&val, (GDExtensionVariantPtr)p_args[2]);
        fluid_synth_cc(engine->synth, (int)chan, (int)ctrl, (int)val);
    }
}

// --- Method 8: all_notes_off(channel: int = -1) -> void ---
static void call_all_notes_off(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine && engine->synth) {
        int64_t chan = -1;
        if (p_argument_count > 0 && p_args[0]) {
            g_to_int(&chan, (GDExtensionVariantPtr)p_args[0]);
        }
        if (chan < 0) {
            for (int c = 0; c < 16; c++) {
                fluid_synth_all_notes_off(engine->synth, c);
            }
        } else {
            fluid_synth_all_notes_off(engine->synth, (int)chan);
        }
    }
}

// --- Method 9: set_gain(gain: float) -> void ---
static void call_set_gain(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine && engine->synth && p_argument_count > 0 && p_args[0]) {
        double gain = 0.2;
        g_to_float(&gain, (GDExtensionVariantPtr)p_args[0]);
        fluid_synth_set_gain(engine->synth, (float)gain);
    }
}

// --- Method 10: set_reverb(enabled: bool, roomsize: float = 0.61, damp: float = 0.23, width: float = 0.76, level: float = 0.61) -> void ---
static void call_set_reverb(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine && engine->synth && p_argument_count >= 1) {
        uint8_t enabled = 1;
        g_to_bool(&enabled, (GDExtensionVariantPtr)p_args[0]);
        double roomsize = 0.61, damp = 0.23, width = 0.76, level = 0.61;
        if (p_argument_count > 1 && p_args[1]) g_to_float(&roomsize, (GDExtensionVariantPtr)p_args[1]);
        if (p_argument_count > 2 && p_args[2]) g_to_float(&damp, (GDExtensionVariantPtr)p_args[2]);
        if (p_argument_count > 3 && p_args[3]) g_to_float(&width, (GDExtensionVariantPtr)p_args[3]);
        if (p_argument_count > 4 && p_args[4]) g_to_float(&level, (GDExtensionVariantPtr)p_args[4]);

        fluid_synth_reverb_on(engine->synth, -1, enabled ? 1 : 0);
        fluid_synth_set_reverb_group_roomsize(engine->synth, -1, roomsize);
        fluid_synth_set_reverb_group_damp(engine->synth, -1, damp);
        fluid_synth_set_reverb_group_width(engine->synth, -1, width);
        fluid_synth_set_reverb_group_level(engine->synth, -1, level);
    }
}

// --- Method 11: is_active() -> bool ---
static void call_is_active(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    uint8_t res = (engine && engine->is_active) ? 1 : 0;
    if (r_return) g_from_bool(r_return, &res);
}

// --- Method 12: close() -> void ---
static void call_close(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    FluidSynthEngine *engine = (FluidSynthEngine *)p_instance;
    if (engine) {
        engine_cleanup(engine);
    }
}

// --- Helper to register a method ---
static void register_method(
    const char *method_name,
    GDExtensionClassMethodCall call_func,
    bool has_return,
    GDExtensionVariantType return_type,
    int arg_count,
    const char **arg_names,
    const GDExtensionVariantType *arg_types
) {
    char mname_buf[32];
    g_string_name_new_with_utf8_chars(SNAME(mname_buf), method_name);

    GDExtensionPropertyInfo ret_info;
    memset(&ret_info, 0, sizeof(ret_info));
    if (has_return) {
        ret_info.type = return_type;
        ret_info.name = SNAME(g_strname_empty_buf);
        ret_info.class_name = SNAME(g_strname_empty_buf);
        ret_info.hint_string = STR(g_str_empty_buf);
        ret_info.usage = 6;
    }

    GDExtensionPropertyInfo *args_info = NULL;
    GDExtensionClassMethodArgumentMetadata *args_meta = NULL;
    char (*arg_snames)[32] = NULL;

    if (arg_count > 0) {
        args_info = (GDExtensionPropertyInfo *)calloc(arg_count, sizeof(GDExtensionPropertyInfo));
        args_meta = (GDExtensionClassMethodArgumentMetadata *)calloc(arg_count, sizeof(GDExtensionClassMethodArgumentMetadata));
        arg_snames = (char (*)[32])calloc(arg_count, 32);

        for (int i = 0; i < arg_count; i++) {
            g_string_name_new_with_utf8_chars(SNAME(arg_snames[i]), arg_names[i]);
            args_info[i].type = arg_types[i];
            args_info[i].name = SNAME(arg_snames[i]);
            args_info[i].class_name = SNAME(g_strname_empty_buf);
            args_info[i].hint_string = STR(g_str_empty_buf);
            args_info[i].usage = 6;
            args_meta[i] = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
        }
    }

    GDExtensionClassMethodInfo minfo;
    memset(&minfo, 0, sizeof(minfo));
    minfo.name = SNAME(mname_buf);
    minfo.call_func = call_func;
    minfo.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    minfo.has_return_value = has_return ? 1 : 0;
    minfo.return_value_info = has_return ? &ret_info : NULL;
    minfo.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    minfo.argument_count = (uint32_t)arg_count;
    minfo.arguments_info = args_info;
    minfo.arguments_metadata = args_meta;

    g_classdb_register_extension_class_method(g_library, SNAME_CONST(g_strname_engine_buf), &minfo);

    if (args_info) free(args_info);
    if (args_meta) free(args_meta);
    if (arg_snames) free(arg_snames);
}

// --- Initialization / Deinitialization ---
static void initialize_level(void *userdata, GDExtensionInitializationLevel level) {
    if (level == GDEXTENSION_INITIALIZATION_SCENE) {
        g_string_name_new_with_utf8_chars(SNAME(g_strname_ref_counted_buf), "RefCounted");
        g_string_name_new_with_utf8_chars(SNAME(g_strname_engine_buf), "FluidSynthEngine");
        g_string_name_new_with_utf8_chars(SNAME(g_strname_empty_buf), "");
        g_string_new_with_utf8_chars(STR(g_str_empty_buf), "");

        // Register FluidSynthEngine with backward-compatible fallback across Godot 4.1 - 4.7+
        if (g_classdb_register_extension_class6) {
            GDExtensionClassCreationInfo6 cinfo;
            memset(&cinfo, 0, sizeof(cinfo));
            cinfo.is_virtual = false;
            cinfo.is_abstract = false;
            cinfo.is_exposed = true;
            cinfo.is_runtime = true;
            cinfo.create_instance_func = fluidsynth_create_instance;
            cinfo.free_instance_func = fluidsynth_free_instance;

            g_classdb_register_extension_class6(
                g_library,
                SNAME_CONST(g_strname_engine_buf),
                SNAME_CONST(g_strname_ref_counted_buf),
                &cinfo
            );
        } else if (g_classdb_register_extension_class3) {
            GDExtensionClassCreationInfo3 cinfo;
            memset(&cinfo, 0, sizeof(cinfo));
            cinfo.is_virtual = false;
            cinfo.is_abstract = false;
            cinfo.is_exposed = true;
            cinfo.is_runtime = true;
            cinfo.create_instance_func = (GDExtensionClassCreateInstance)fluidsynth_create_instance;
            cinfo.free_instance_func = fluidsynth_free_instance;

            g_classdb_register_extension_class3(
                g_library,
                SNAME_CONST(g_strname_engine_buf),
                SNAME_CONST(g_strname_ref_counted_buf),
                &cinfo
            );
        } else if (g_classdb_register_extension_class2) {
            GDExtensionClassCreationInfo2 cinfo;
            memset(&cinfo, 0, sizeof(cinfo));
            cinfo.is_virtual = false;
            cinfo.is_abstract = false;
            cinfo.is_exposed = true;
            cinfo.create_instance_func = (GDExtensionClassCreateInstance)fluidsynth_create_instance;
            cinfo.free_instance_func = fluidsynth_free_instance;

            g_classdb_register_extension_class2(
                g_library,
                SNAME_CONST(g_strname_engine_buf),
                SNAME_CONST(g_strname_ref_counted_buf),
                &cinfo
            );
        } else if (g_classdb_register_extension_class) {
            GDExtensionClassCreationInfo cinfo;
            memset(&cinfo, 0, sizeof(cinfo));
            cinfo.is_virtual = false;
            cinfo.is_abstract = false;
            cinfo.create_instance_func = (GDExtensionClassCreateInstance)fluidsynth_create_instance;
            cinfo.free_instance_func = fluidsynth_free_instance;

            g_classdb_register_extension_class(
                g_library,
                SNAME_CONST(g_strname_engine_buf),
                SNAME_CONST(g_strname_ref_counted_buf),
                &cinfo
            );
        }

        // 1. init_synth(gain: float = 0.2) -> bool
        {
            const char *anames[] = { "gain" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_FLOAT };
            register_method("init_synth", call_init_synth, true, GDEXTENSION_VARIANT_TYPE_BOOL, 1, anames, atypes);
        }

        // 2. render_frames(count: int) -> PackedVector2Array
        {
            const char *anames[] = { "count" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_INT };
            register_method("render_frames", call_render_frames, true, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, 1, anames, atypes);
        }

        // 3. load_soundfont(path: String) -> int
        {
            const char *anames[] = { "path" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_STRING };
            register_method("load_soundfont", call_load_soundfont, true, GDEXTENSION_VARIANT_TYPE_INT, 1, anames, atypes);
        }

        // 4. note_on(channel: int, key: int, velocity: int) -> void
        {
            const char *anames[] = { "channel", "key", "velocity" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT };
            register_method("note_on", call_note_on, false, GDEXTENSION_VARIANT_TYPE_NIL, 3, anames, atypes);
        }

        // 5. note_off(channel: int, key: int) -> void
        {
            const char *anames[] = { "channel", "key" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT };
            register_method("note_off", call_note_off, false, GDEXTENSION_VARIANT_TYPE_NIL, 2, anames, atypes);
        }

        // 6. pitch_bend(channel: int, value: int) -> void
        {
            const char *anames[] = { "channel", "value" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT };
            register_method("pitch_bend", call_pitch_bend, false, GDEXTENSION_VARIANT_TYPE_NIL, 2, anames, atypes);
        }

        // 7. control_change(channel: int, controller: int, value: int) -> void
        {
            const char *anames[] = { "channel", "controller", "value" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT };
            register_method("control_change", call_control_change, false, GDEXTENSION_VARIANT_TYPE_NIL, 3, anames, atypes);
        }

        // 8. all_notes_off(channel: int = -1) -> void
        {
            const char *anames[] = { "channel" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_INT };
            register_method("all_notes_off", call_all_notes_off, false, GDEXTENSION_VARIANT_TYPE_NIL, 1, anames, atypes);
        }

        // 9. set_gain(gain: float) -> void
        {
            const char *anames[] = { "gain" };
            const GDExtensionVariantType atypes[] = { GDEXTENSION_VARIANT_TYPE_FLOAT };
            register_method("set_gain", call_set_gain, false, GDEXTENSION_VARIANT_TYPE_NIL, 1, anames, atypes);
        }

        // 10. set_reverb(enabled: bool, roomsize: float = 0.61, damp: float = 0.23, width: float = 0.76, level: float = 0.61) -> void
        {
            const char *anames[] = { "enabled", "roomsize", "damp", "width", "level" };
            const GDExtensionVariantType atypes[] = {
                GDEXTENSION_VARIANT_TYPE_BOOL,
                GDEXTENSION_VARIANT_TYPE_FLOAT,
                GDEXTENSION_VARIANT_TYPE_FLOAT,
                GDEXTENSION_VARIANT_TYPE_FLOAT,
                GDEXTENSION_VARIANT_TYPE_FLOAT
            };
            register_method("set_reverb", call_set_reverb, false, GDEXTENSION_VARIANT_TYPE_NIL, 5, anames, atypes);
        }

        // 11. is_active() -> bool
        {
            register_method("is_active", call_is_active, true, GDEXTENSION_VARIANT_TYPE_BOOL, 0, NULL, NULL);
        }

        // 12. close() -> void
        {
            register_method("close", call_close, false, GDEXTENSION_VARIANT_TYPE_NIL, 0, NULL, NULL);
        }
    }
}

static void deinitialize_level(void *userdata, GDExtensionInitializationLevel level) {
    if (level == GDEXTENSION_INITIALIZATION_SCENE) {
        // Cleanup if needed
    }
}

// --- Entry Point ---
extern "C" GD_EXPORT GDExtensionBool fluidsynth_bridge_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization *r_initialization
) {
    g_get_proc_address = p_get_proc_address;
    g_library = p_library;

    g_string_name_new_with_utf8_chars = (GDExtensionInterfaceStringNameNewWithUtf8Chars)p_get_proc_address("string_name_new_with_utf8_chars");
    g_string_new_with_utf8_chars = (GDExtensionInterfaceStringNewWithUtf8Chars)p_get_proc_address("string_new_with_utf8_chars");
    g_string_to_utf8_chars = (GDExtensionInterfaceStringToUtf8Chars)p_get_proc_address("string_to_utf8_chars");
    g_variant_destroy = (GDExtensionInterfaceVariantDestroy)p_get_proc_address("variant_destroy");

    g_get_variant_to_type_constructor = (GDExtensionInterfaceGetVariantToTypeConstructor)p_get_proc_address("get_variant_to_type_constructor");
    g_get_variant_from_type_constructor = (GDExtensionInterfaceGetVariantFromTypeConstructor)p_get_proc_address("get_variant_from_type_constructor");

    if (g_get_variant_to_type_constructor) {
        g_to_int = g_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_INT);
        g_to_float = g_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_FLOAT);
        g_to_bool = g_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_BOOL);
        g_to_string = g_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_STRING);
    }

    if (g_get_variant_from_type_constructor) {
        g_from_int = g_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_INT);
        g_from_float = g_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_FLOAT);
        g_from_bool = g_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_BOOL);
        g_from_pv2 = g_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
    }

    g_classdb_construct_object3 = (GDExtensionInterfaceClassdbConstructObject3)p_get_proc_address("classdb_construct_object3");
    g_classdb_construct_object = (GDExtensionInterfaceClassdbConstructObject)p_get_proc_address("classdb_construct_object");
    g_object_set_instance = (GDExtensionInterfaceObjectSetInstance)p_get_proc_address("object_set_instance");

    g_classdb_register_extension_class6 = (GDExtensionInterfaceClassdbRegisterExtensionClass6)p_get_proc_address("classdb_register_extension_class6");
    if (!g_classdb_register_extension_class6) {
        g_classdb_register_extension_class3 = (GDExtensionInterfaceClassdbRegisterExtensionClass3)p_get_proc_address("classdb_register_extension_class3");
        if (!g_classdb_register_extension_class3) {
            g_classdb_register_extension_class2 = (GDExtensionInterfaceClassdbRegisterExtensionClass2)p_get_proc_address("classdb_register_extension_class2");
            if (!g_classdb_register_extension_class2) {
                g_classdb_register_extension_class = (GDExtensionInterfaceClassdbRegisterExtensionClass)p_get_proc_address("classdb_register_extension_class");
            }
        }
    }
    g_classdb_register_extension_class_method = (GDExtensionInterfaceClassdbRegisterExtensionClassMethod)p_get_proc_address("classdb_register_extension_class_method");

    g_packed_vector2_array_operator_index = (GDExtensionInterfacePackedVector2ArrayOperatorIndex)p_get_proc_address("packed_vector2_array_operator_index");
    
    GDExtensionInterfaceVariantGetPtrConstructor get_ptr_ctor = (GDExtensionInterfaceVariantGetPtrConstructor)p_get_proc_address("variant_get_ptr_constructor");
    if (get_ptr_ctor) {
        g_pv2_ctor = get_ptr_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, 0);
    }

    GDExtensionInterfaceVariantGetPtrDestructor get_ptr_dtor = (GDExtensionInterfaceVariantGetPtrDestructor)p_get_proc_address("variant_get_ptr_destructor");
    if (get_ptr_dtor) {
        g_pv2_dtor = get_ptr_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
    }

    GDExtensionInterfaceVariantGetPtrBuiltinMethod get_ptr_method = (GDExtensionInterfaceVariantGetPtrBuiltinMethod)p_get_proc_address("variant_get_ptr_builtin_method");
    if (get_ptr_method && g_string_name_new_with_utf8_chars) {
        char sname_resize[32];
        g_string_name_new_with_utf8_chars(SNAME(sname_resize), "resize");
        g_pv2_resize = get_ptr_method(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, SNAME_CONST(sname_resize), 848867239);
    }

    r_initialization->initialize = initialize_level;
    r_initialization->deinitialize = deinitialize_level;
    r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;

    return 1;
}
