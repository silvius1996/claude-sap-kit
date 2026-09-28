// Project safety rules, read from the environment variables of the ARC-1 server (project .mcp.json).
// They differ from system to system: with a shared SAP user the author check makes no sense.
// The author check is done in ABAP with the user actually logged on: here we only read whether to enable it.

export interface ProjectRules {
  transportWrites: boolean;
  allowedPackages: string[];
  checkAuthor: boolean;
  allowedTransports?: string[];
}

function list(value: string | undefined): string[] {
  return (value ?? '')
    .split(',')
    .map((item) => item.trim().toUpperCase())
    .filter(Boolean);
}

export function readRules(env: NodeJS.ProcessEnv = process.env): ProjectRules {
  const transports = list(env.ZAI_ALLOWED_TRANSPORTS);
  return {
    transportWrites: env.SAP_ALLOW_TRANSPORT_WRITES?.trim().toLowerCase() === 'true',
    allowedPackages: list(env.SAP_ALLOWED_PACKAGES),
    checkAuthor: env.ZAI_CHECK_AUTHOR?.trim().toLowerCase() !== 'false',
    allowedTransports: transports.length ? transports : undefined,
  };
}

export function matchesPackage(devclass: string, patterns: string[]): boolean {
  const name = devclass.trim().toUpperCase();
  return patterns.some((pattern) => {
    const regex = pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
    return new RegExp(`^${regex}$`).test(name);
  });
}

export function checkReplaceRules(rules: ProjectRules, target: { devclass: string; transport: string }): string[] {
  const errors: string[] = [];
  if (rules.allowedPackages.length === 0) {
    errors.push('SAP_ALLOWED_PACKAGES not set in .mcp.json: replacement not allowed');
  } else if (!matchesPackage(target.devclass, rules.allowedPackages)) {
    errors.push(`Package ${target.devclass} not allowed (SAP_ALLOWED_PACKAGES: ${rules.allowedPackages.join(',')})`);
  }
  const transport = target.transport.trim().toUpperCase();
  if (rules.allowedTransports && !rules.allowedTransports.includes(transport)) {
    errors.push(`Transport request ${transport} is not among the allowed ones (ZAI_ALLOWED_TRANSPORTS)`);
  }
  return errors;
}
