{{flutter_js}}
{{flutter_build_config}}

const startup = window.jidiuStartup;
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      startup?.update('正在准备棋盘…');
      const appRunner = await engineInitializer.initializeEngine();
      startup?.update('即将进入棋室…');
      await appRunner.runApp();
    } catch (error) {
      startup?.fail(error);
    }
  },
}).catch((error) => startup?.fail(error));
