# ExampleProtocol — iOS Layer Architecture

```
      ┌─────────────────────┐                              ┌───────────────────────┐
      │    Swift Callers    │                              │  Objective-C Callers  │
      └──────────┬──────────┘                              └───────────┬───────────┘
                 │ retains                                             │ retains
                 │                                       ┌─────────────▼─────────────┐
                 │                                       │    ExampleProtocolShim    │
                 │                                       └──────────────┬────────────┘
                 └──────────────────┐                   ┌───────────────┘ retains
                                    ▼                   ▼
                              ┌──────────────────────────────────┐
                              │          ExampleProtocol         │
                              └─┬──────────────────────────────┬─┘
                        depends │                              │ conforms
             ┌──────────────────┘                              └─────────────┐
             ▼                                                               ▼
┌──────────────────────────────────────┐   ┌────────────────────────────────────────┐
│ ExampleProtocolCoreListenerInterface │   │     ExampleProtocolPlatformInterface   │
└──────────────┬───────────────────────┘   └───────────────────▲────────────────────┘
               │                                               │ weak delegate
               │                           ┌───────────────────┴────────────────────┐
               │                           │     ExampleProtocolPlatformWrapper     │
               │                           │ (retained by ExampleProtocolPlatform)  │
               │                           └───────────────────┬────────────────────┘
               │ conforms                                      │ conforms
               ▼                                               ▼
┌────────────────────────────────────┐     ┌────────────────────────────────────────┐
│  RBXIExampleProtocolCoreListener   │     │       RBXIPlatformExampleProtocol      │
│      (calls into Engine)           │     │           (called by Engine)           │
└────────────────────────────────────┘     └────────────────────────────────────────┘
```
