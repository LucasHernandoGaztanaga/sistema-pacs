window.config = {
  routerBasename: '/',
  extensions: [],
  modes: [],
  customizationService: {},
  showStudyList: true,
  maxNumberOfWebWorkers: 4,
  filterQueryParam: false,
  httpErrorHandler: error => {
    console.warn(error.status);
  },
  defaultDataSourceName: 'dicomweb',
  investigationalUseDialog: {
    option: 'never'
  },
  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.dicomweb',
      sourceName: 'dicomweb',
      configuration: {
        friendlyName: 'DCM4CHEE PACS Server',
        name: 'DCM4CHEE',
        wadoUriRoot: 'http://localhost:8080/dcm4chee-arc/aets/DCM4CHEE/wado',
        qidoRoot: 'http://localhost:8080/dcm4chee-arc/aets/DCM4CHEE/rs',
        wadoRoot: 'http://localhost:8080/dcm4chee-arc/aets/DCM4CHEE/rs',
        qidoSupportsIncludeField: true,
        supportsReject: true,
        imageRendering: 'wadors',
        thumbnailRendering: 'wadors',
        enableStudyLazyLoad: true,
        supportsFuzzyMatching: true,
        supportsWildcard: true,
        staticWado: true,
        singlepart: 'bulkdata,video',
        acceptHeader: ['multipart/related; type=application/octet-stream; transfer-syntax=*'],
        bulkDataURI: {
          enabled: true,
          relativeResolution: 'studies',
        },
        omitQuotationForMultipartRequest: true,
      },
    },
  ],
  // Configuración de los estudios por defecto
  studyListFunctionsEnabled: true,
  // Configuración de herramientas
  cornerstoneExtensionConfig: {
    tools: {
      ArrowAnnotate: {
        configuration: {
          getTextCallback: (callback, eventDetails) => {
            callback(prompt('Ingrese anotación:'));
          },
        },
      },
    },
  },
  // Configuración de la interfaz de usuario
  customizationService: {
    dicomUploadComponent:
      '@ohif/extension-cornerstone.customizationModule.dicomUploadComponent',
  },
  // Configuración de los modos de visualización
  maxNumRequests: {
    interaction: 100,
    thumbnail: 75,
    prefetch: 25,
  },
  // Configuración de la barra de herramientas
  showWarningMessageForCrossOrigin: false,
  showCPUFallbackMessage: false,
  showLoadingIndicator: true,
  strictZSpacingForVolumeViewport: true,
};