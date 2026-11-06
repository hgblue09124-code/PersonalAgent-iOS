#import "PythonRuntimeBridge.h"

#include <Python.h>

static NSString * const PAPythonRuntimeErrorDomain = @"app.personalagent.python-runtime";

static NSError *PAError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:PAPythonRuntimeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *PAStatusMessage(PyStatus status) {
    if (status.err_msg != NULL) {
        return [NSString stringWithUTF8String:status.err_msg] ?: @"Unknown CPython initialization error.";
    }
    return @"CPython initialization failed.";
}

static wchar_t *PAWideString(NSString *value) {
    return Py_DecodeLocale(value.UTF8String ?: "", NULL);
}

static BOOL PASetConfigString(PyConfig *config, wchar_t **field, NSString *value, NSError **error) {
    wchar_t *wideValue = PAWideString(value);
    if (wideValue == NULL) {
        if (error != NULL) *error = PAError(10, @"Unable to encode a CPython configuration path.");
        return NO;
    }
    PyStatus status = PyConfig_SetString(config, field, wideValue);
    PyMem_RawFree(wideValue);
    if (PyStatus_Exception(status)) {
        if (error != NULL) *error = PAError(11, PAStatusMessage(status));
        return NO;
    }
    return YES;
}

static BOOL PAAppendModulePath(PyConfig *config, NSString *path, NSError **error) {
    wchar_t *widePath = PAWideString(path);
    if (widePath == NULL) {
        if (error != NULL) *error = PAError(12, @"Unable to encode a CPython module search path.");
        return NO;
    }
    PyStatus status = PyWideStringList_Append(&config->module_search_paths, widePath);
    PyMem_RawFree(widePath);
    if (PyStatus_Exception(status)) {
        if (error != NULL) *error = PAError(13, PAStatusMessage(status));
        return NO;
    }
    return YES;
}

static NSString *PAConsumePythonError(void) {
    if (!PyErr_Occurred()) return @"The Python planner returned no result.";

    PyObject *type = NULL;
    PyObject *value = NULL;
    PyObject *traceback = NULL;
    PyErr_Fetch(&type, &value, &traceback);
    PyErr_NormalizeException(&type, &value, &traceback);

    PyObject *description = PyObject_Str(value != NULL ? value : type);
    const char *utf8 = description != NULL ? PyUnicode_AsUTF8(description) : NULL;
    NSString *message = utf8 != NULL
        ? [NSString stringWithUTF8String:utf8]
        : @"The embedded Python planner raised an exception.";

    Py_XDECREF(description);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(traceback);
    PyErr_Clear();
    return message;
}

@implementation PAPythonRuntimeBridge

+ (BOOL)initializeRuntimeWithError:(NSError **)error {
    static dispatch_once_t onceToken;
    static BOOL initialized = NO;
    static NSError *initializationError = nil;

    dispatch_once(&onceToken, ^{
        NSString *resourcePath = NSBundle.mainBundle.resourcePath;
        if (resourcePath.length == 0) {
            initializationError = PAError(1, @"The app bundle resource path is unavailable.");
            return;
        }

        NSString *pythonHome = [resourcePath stringByAppendingPathComponent:@"python"];
        NSString *pythonLibrary = [pythonHome stringByAppendingPathComponent:@"lib/python3.15"];
        NSString *pythonDynamicModules = [pythonLibrary stringByAppendingPathComponent:@"lib-dynload"];
        NSString *applicationModules = [resourcePath stringByAppendingPathComponent:@"app"];

        NSFileManager *fileManager = NSFileManager.defaultManager;
        if (![fileManager fileExistsAtPath:pythonHome] ||
            ![fileManager fileExistsAtPath:pythonLibrary] ||
            ![fileManager fileExistsAtPath:applicationModules]) {
            initializationError = PAError(2, @"The bundled CPython runtime or Agent planner package is missing.");
            return;
        }

        PyPreConfig preConfig;
        PyPreConfig_InitIsolatedConfig(&preConfig);
        preConfig.utf8_mode = 1;

        PyStatus status = Py_PreInitialize(&preConfig);
        if (PyStatus_Exception(status)) {
            initializationError = PAError(3, PAStatusMessage(status));
            return;
        }

        PyConfig config;
        PyConfig_InitIsolatedConfig(&config);
        config.parse_argv = 0;
        config.use_environment = 0;
        config.user_site_directory = 0;
        config.buffered_stdio = 0;
        config.write_bytecode = 0;
        config.install_signal_handlers = 1;
        config.use_system_logger = 1;
        config.module_search_paths_set = 1;

        NSError *configurationError = nil;
        BOOL configured =
            PASetConfigString(&config, &config.program_name, @"PersonalAgent", &configurationError) &&
            PASetConfigString(&config, &config.home, pythonHome, &configurationError) &&
            PAAppendModulePath(&config, pythonLibrary, &configurationError) &&
            PAAppendModulePath(&config, pythonDynamicModules, &configurationError) &&
            PAAppendModulePath(&config, applicationModules, &configurationError);

        if (!configured) {
            PyConfig_Clear(&config);
            initializationError = configurationError ?: PAError(4, @"Unable to configure embedded CPython.");
            return;
        }

        status = Py_InitializeFromConfig(&config);
        PyConfig_Clear(&config);
        if (PyStatus_Exception(status)) {
            initializationError = PAError(5, PAStatusMessage(status));
            return;
        }

        // Release the initialization thread's GIL. Each planner invocation
        // acquires it explicitly, while the Swift actor serializes requests.
        PyEval_SaveThread();
        initialized = YES;
    });

    if (!initialized && error != NULL) {
        *error = initializationError ?: PAError(6, @"Embedded CPython is unavailable.");
    }
    return initialized;
}

+ (NSString *)planRequestWithText:(NSString *)text
                  allowedSkillIDs:(NSArray<NSString *> *)allowedSkillIDs
                            error:(NSError **)error {
    NSError *initializationError = nil;
    if (![self initializeRuntimeWithError:&initializationError]) {
        if (error != NULL) *error = initializationError;
        return nil;
    }

    PyGILState_STATE gilState = PyGILState_Ensure();
    NSString *result = nil;
    NSError *planningError = nil;

    PyObject *plannerModule = PyImport_ImportModule("personal_agent_runtime.planner");
    PyObject *plannerFunction = plannerModule != NULL
        ? PyObject_GetAttrString(plannerModule, "plan_request")
        : NULL;
    PyObject *pythonText = PyUnicode_FromString(text.UTF8String ?: "");
    PyObject *pythonAllowedSkills = PyList_New(0);

    if (pythonAllowedSkills != NULL) {
        for (NSString *skillID in allowedSkillIDs) {
            PyObject *pythonSkillID = PyUnicode_FromString(skillID.UTF8String ?: "");
            if (pythonSkillID == NULL || PyList_Append(pythonAllowedSkills, pythonSkillID) != 0) {
                Py_XDECREF(pythonSkillID);
                break;
            }
            Py_DECREF(pythonSkillID);
        }
    }

    PyObject *arguments = (pythonText != NULL && pythonAllowedSkills != NULL)
        ? PyTuple_Pack(2, pythonText, pythonAllowedSkills)
        : NULL;
    PyObject *plan = (plannerFunction != NULL && arguments != NULL)
        ? PyObject_CallObject(plannerFunction, arguments)
        : NULL;
    PyObject *planDictionary = plan != NULL
        ? PyObject_CallMethod(plan, "to_dict", NULL)
        : NULL;
    PyObject *jsonModule = planDictionary != NULL
        ? PyImport_ImportModule("json")
        : NULL;
    PyObject *jsonString = jsonModule != NULL
        ? PyObject_CallMethod(jsonModule, "dumps", "O", planDictionary)
        : NULL;

    if (jsonString != NULL) {
        const char *utf8 = PyUnicode_AsUTF8(jsonString);
        if (utf8 != NULL) {
            result = [NSString stringWithUTF8String:utf8];
        }
    }

    if (result == nil) {
        planningError = PAError(20, PAConsumePythonError());
    }

    Py_XDECREF(jsonString);
    Py_XDECREF(jsonModule);
    Py_XDECREF(planDictionary);
    Py_XDECREF(plan);
    Py_XDECREF(arguments);
    Py_XDECREF(pythonAllowedSkills);
    Py_XDECREF(pythonText);
    Py_XDECREF(plannerFunction);
    Py_XDECREF(plannerModule);

    PyGILState_Release(gilState);

    if (result == nil && error != NULL) {
        *error = planningError ?: PAError(21, @"The embedded Python planner returned an invalid result.");
    }
    return result;
}

@end
