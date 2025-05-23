/*
 * If not stated otherwise in this file or this component's LICENSE file
 * the following copyright and licenses apply:
 *
 * Copyright 2016 RDK Management
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
*/

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include <string.h>
#include <getopt.h>
#include <rbus.h>
#include <rtMemory.h>

#include <rtMemory.h>


#define NUMBER_OF_DATA_ELEMENTS 1

#define DATA_HANDLER_MACRO \
    { \
        multiRbusProvider_SampleDataGetHandler, \
        multiRbusProvider_SampleDataSetHandler, \
        NULL, \
        NULL, \
        NULL, \
        NULL \
    }

#define RRD_DATA_HANDLER_MACRO \
    { \
        rrdDataGetHandler, \
        rrdDataSetHandler, \
        NULL, \
        NULL, \
        NULL, \
        NULL \
    }

rbusHandle_t handle1;
rbusError_t multiRbusProvider_SampleDataGetHandler(rbusHandle_t handle, rbusProperty_t prop, rbusGetHandlerOptions_t* opts);
rbusError_t multiRbusProvider_SampleDataSetHandler(rbusHandle_t handle, rbusProperty_t property, rbusSetHandlerOptions_t* opts);
rbusError_t rrdDataGetHandler(rbusHandle_t handle, rbusProperty_t prop, rbusGetHandlerOptions_t* opts);
rbusError_t rrdDataSetHandler(rbusHandle_t handle, rbusProperty_t property, rbusSetHandlerOptions_t* opts);

// Add a string array to store the data element values
char dataElementValues[NUMBER_OF_DATA_ELEMENTS][256];
bool rdkRemoteDebuggerIssueType = false;

char* dataElemenInitValues[NUMBER_OF_DATA_ELEMENTS] = {
    "false"
};

void init_dataElementValues()
{
    for (int i = 0; i < NUMBER_OF_DATA_ELEMENTS; i++)
    {
        memset(dataElementValues[i], 0, 256);
        strcpy(dataElementValues[i], dataElemenInitValues[i]);
    }
}

// Add a string array to store the data element names
 char* const dataElementNames[NUMBER_OF_DATA_ELEMENTS] = {
    "Device.X_RDK_WebConfig.webcfgSubdocForceReset"
};


/**
 * @brief Structure representing a data element in the rbusDataElement_t array.
 */
rbusDataElement_t dataElements[NUMBER_OF_DATA_ELEMENTS] = {
    {
        dataElementNames[0], // The name of the data element
        RBUS_ELEMENT_TYPE_PROPERTY, // The type of the data element
        DATA_HANDLER_MACRO
    }
};


 

/**
 * @brief Signal handler function for handling the exit signal.
 * 
 * This function is called when the program receives an exit signal. It performs the following tasks:
 * - Unregisters data elements from two handles (handle1) using the rbus_unregDataElements function.
 * - Closes handle1 using the rbus_close function.
 * - Prints a message indicating that the provider is exiting.
 * - Calls the exit function to terminate the program.
 * 
 * @param sig The signal number.
 */
void exitHandler(int sig)
{
    printf("Caught signal %d\n", sig);

    int rc1 = rbus_unregDataElements(handle1, 1, dataElements);
    if (rc1 != RBUS_ERROR_INVALID_HANDLE)
    {
        printf("provider: rbus_unregDataElements for handle1 err: %d\n", rc1);
    }
   
    rc1 = rbus_close(handle1);
    if (rc1 != RBUS_ERROR_INVALID_HANDLE)
    {
        printf("consumer: rbus_close handle1 err: %d\n", rc1);
    }
    printf("provider: exit\n");
    exit(0);
}

int main(int argc, char* argv[])
{
    (void)(argc);
    (void)(argv);


    int rc1 = RBUS_ERROR_SUCCESS;

    char componentName[] = "rfc_provider_for_platform";
    init_dataElementValues();

    printf("provider: start\n");

    rc1 = rbus_open(&handle1, componentName);
    if (rc1 != RBUS_ERROR_SUCCESS)
    {
        printf("provider: First rbus_open for handle1 err: %d\n", rc1);
        goto exit1;
    }
  
    rc1 = rbus_regDataElements(handle1, NUMBER_OF_DATA_ELEMENTS, dataElements);
  
    // Add exit handler to catch signals and close rbus handles
    signal(SIGINT, exitHandler);
    signal(SIGTERM, exitHandler);

    while (1)
    {
        // Your code here
        printf("provider: running ...\n");
        sleep(1);
    }

exit2:
    rc1 = rbus_close(handle1);
    if (rc1 != RBUS_ERROR_INVALID_HANDLE)
    {
        printf("consumer: rbus_close handle1 err: %d\n", rc1);
    }

exit1:
    printf("provider: exit\n");
    exit(0);
}

rbusError_t multiRbusProvider_SampleDataSetHandler(rbusHandle_t handle, rbusProperty_t prop, rbusSetHandlerOptions_t* opts)
{
    (void)handle;
    (void)opts;

    char const* name = rbusProperty_GetName(prop);
    rbusValue_t value = rbusProperty_GetValue(prop);
    rbusValueType_t type = rbusValue_GetType(value);

    printf("Called set handler for [%s]\n", name);

 // For loop to iterate through the data element names and check if the name matches the name of the data element
    for (int i = 0; i < NUMBER_OF_DATA_ELEMENTS; i++)
    {
        printf("dataElementNames[%d] = %s\n", i, dataElementNames[i]);
        if (strcmp(name, dataElementNames[i]) == 0)
        {
            if (type == RBUS_STRING)
            {
                printf("String Value set handler\n");
                int len = 0;
                char const* data = NULL;
                data = rbusValue_GetString(value, &len);
                printf("Called set handler for [%s] & value is %s\n", name, data);
                // Clear the value in dataElementValues array
                memset(dataElementValues[i], 0, strlen(dataElementValues[i]));
                // Copy the new value to the dataElementValues array
                strcpy(dataElementValues[i], data);
                printf("Done setting value");
            }
            else if (type == RBUS_BOOLEAN)
            {
                printf("Boolean Value set handler\n");
                bool data = rbusValue_GetBoolean(value);
                printf("Called set handler for [%s] & value is %s\n", name, data ? "true" : "false");
                // Clear the value in dataElementValues array
                memset(dataElementValues[i], 0, strlen(dataElementValues[i]));
                // Copy the new value to the dataElementValues array
                strcpy(dataElementValues[i], data ? "true" : "false");
                printf("Done setting value\n");
            }
            else
            {
                printf("Cant Handle [%s]\n", name);
                return RBUS_ERROR_INVALID_INPUT;
            }
            break;            
        }
    }

    return RBUS_ERROR_SUCCESS;
}

rbusError_t multiRbusProvider_SampleDataGetHandler(rbusHandle_t handle, rbusProperty_t property, rbusGetHandlerOptions_t* opts)
{
    (void)handle;
    (void)opts;
    rbusValue_t value;
    int intData = 0;
    char const* name;

    rbusValue_Init(&value);
    name = rbusProperty_GetName(property);

    // For loop to iterate through the data element names and check if the name matches the name of the data element
    for (int i = 0; i < NUMBER_OF_DATA_ELEMENTS; i++)
    {
        if (strcmp(name, dataElementNames[i]) == 0)
        {
            rbusValue_SetString(value, dataElementValues[i]);
            break;
        }
    }   

    rbusProperty_SetValue(property, value);
    rbusValue_Release(value);

    return RBUS_ERROR_SUCCESS;
}

rbusError_t rrdDataGetHandler(rbusHandle_t handle, rbusProperty_t property, rbusGetHandlerOptions_t* opts) {
    (void)handle;
    (void)opts;

    const char* name = rbusProperty_GetName(property);
    rbusValue_t value;
    if (strcmp(name, "Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.RDKRemoteDebugger.Enable") == 0) {
        rbusValue_Init(&value);
        rbusValue_SetBoolean(value, rdkRemoteDebuggerIssueType);
        rbusProperty_SetValue(property, value);
        rbusValue_Release(value);
        printf("Get handler: %s = %s\n", name, rdkRemoteDebuggerIssueType ? "true" : "false");
        return RBUS_ERROR_SUCCESS;
    }

    return RBUS_ERROR_BUS_ERROR;
}

rbusError_t rrdDataSetHandler(rbusHandle_t handle, rbusProperty_t property, rbusSetHandlerOptions_t* opts) {
    (void)handle;
    (void)opts;

    const char* name = rbusProperty_GetName(property);
    rbusValue_t value = rbusProperty_GetValue(property);

    if (strcmp(name, "Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.RDKRemoteDebugger.Enable") == 0) {
        rdkRemoteDebuggerIssueType = rbusValue_GetBoolean(value);
        printf("Set handler: %s = %s\n", name, rdkRemoteDebuggerIssueType ? "true" : "false");
        return RBUS_ERROR_SUCCESS;
    }

    return RBUS_ERROR_BUS_ERROR;
}
