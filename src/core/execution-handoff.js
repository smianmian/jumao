export function sandboxExecutionContext(authorizedScope = ['current temporary worktree']) {
  const scope = Array.isArray(authorizedScope) ? authorizedScope : [authorizedScope];
  return {
    executionMode: 'sandbox_implementation',
    authorizedScope: scope.map((item) => String(item)).filter(Boolean),
    allowPrepare: true,
    allowValidate: true,
    allowProductionEffects: false
  };
}

export function renderExecutionContext(context) {
  return JSON.stringify(context, null, 2);
}
