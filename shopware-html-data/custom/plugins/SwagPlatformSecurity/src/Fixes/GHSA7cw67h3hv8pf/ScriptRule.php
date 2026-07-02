<?php declare(strict_types=1);

namespace Shopware\Core\Framework\Rule;

use Shopware\Core\Framework\Adapter\Twig\Extension\ComparisonExtension;
use Shopware\Core\Framework\Adapter\Twig\Extension\PcreExtension;
use Shopware\Core\Framework\Adapter\Twig\Extension\PhpSyntaxExtension;
use Shopware\Core\Framework\Adapter\Twig\Filter\ReplaceRecursiveFilter;
use Shopware\Core\Framework\Adapter\Twig\TwigEnvironment;
use Shopware\Core\Framework\App\Event\Hooks\AppScriptConditionHook;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Script\Debugging\Debug;
use Shopware\Core\Framework\Script\Debugging\ScriptTraces;
use Shopware\Core\Framework\Script\Execution\Hook;
use Shopware\Core\Framework\Script\Execution\Script;
use Shopware\Core\Framework\Script\Execution\ScriptTwigLoader;
use Swag\Security\Fixes\GHSA7cw67h3hv8pf\PatchedSecurityExtension;
use Symfony\Component\Validator\Constraint;
use Twig\Cache\FilesystemCache;
use Twig\Error\LoaderError;
use Twig\Error\RuntimeError;
use Twig\Error\SyntaxError;
use Twig\Extension\DebugExtension;

/**
 * @final
 */
#[Package('fundamentals@after-sales')]
class ScriptRule extends Rule
{
    final public const RULE_NAME = 'scriptRule';

    protected string $script = '';

    /**
     * @var array<string, Constraint[]>
     */
    protected array $constraints = [];

    /**
     * @var array<string, mixed>
     */
    protected array $values = [];

    protected ?\DateTimeInterface $lastModified = null;

    protected ?string $identifier = null;

    protected ?ScriptTraces $traces = null;

    protected ?string $cacheDir = null;

    protected bool $debug = true;

    public function match(RuleScope $scope): bool
    {
        $name = $this->identifier ?? $this->getName();
        $context = [...['scope' => $scope], ...$this->values];
        $lastModified = $this->lastModified ?? $scope->getCurrentTime();

        $twigOptions = ['auto_reload' => true];
        if (!$this->debug) {
            $twigOptions['cache'] = new FilesystemCache($this->cacheDir . '/' . $name);
        } else {
            $twigOptions['debug'] = true;
        }

        // script constructor changed in 6.7.2.0 here: https://github.com/shopware/shopware/commit/54f3b198641e50103126a4707561fa64599b769a
        /** @phpstan-ignore-next-line */
        if (method_exists(Script::class, 'setTwigOptions')) {
            $script = new Script(
                $name,
                \sprintf('
                {%%- macro evaluate(%1$s) -%%}
                    %2$s
                {%%- endmacro -%%}

                {%%- set var = _self.evaluate(%1$s) -%%}
                {{- var -}}
            ', implode(', ', array_keys($context)), $this->script),
                $lastModified,
            );
            $script->setTwigOptions($twigOptions);
        } else {
            $script = new Script(
                $name,
                \sprintf('
                {%%- macro evaluate(%1$s) -%%}
                    %2$s
                {%%- endmacro -%%}

                {%%- set var = _self.evaluate(%1$s) -%%}
                {{- var -}}
            ', implode(', ', array_keys($context)), $this->script),
                $lastModified,
                null,
                /** @phpstan-ignore-next-line */
                $twigOptions
            );
        }

        $twig = new TwigEnvironment(
            new ScriptTwigLoader($script),
            $script->getTwigOptions()
        );

        /** @phpstan-ignore-next-line new.deprecatedClass (This fix mirrors the vulnerable Shopware versions where the class is not internal yet.) */
        $twig->addExtension(new PhpSyntaxExtension());
        $twig->addExtension(new ComparisonExtension());
        /** @phpstan-ignore-next-line new.deprecatedClass (This fix mirrors the vulnerable Shopware versions where the class is not internal yet.) */
        $twig->addExtension(new PcreExtension());
        /** @phpstan-ignore-next-line new.deprecatedClass (This fix mirrors the vulnerable Shopware versions where the class is not internal yet.) */
        $twig->addExtension(new ReplaceRecursiveFilter());

        if ($this->debug) {
            $twig->addExtension(new DebugExtension());
        }

        $twig->addExtension(new PatchedSecurityExtension([]));

        $hook = new AppScriptConditionHook($scope->getContext());

        try {
            return $this->render($twig, $script, $hook, $name, $context);
        } catch (\Throwable $e) {
            throw RuleException::scriptExecutionFailed($hook->getName(), $script->getName(), $e);
        }
    }

    /**
     * @return array<string, Constraint[]>
     */
    public function getConstraints(): array
    {
        return $this->constraints;
    }

    /**
     * @param array<string, Constraint[]> $constraints
     */
    public function setConstraints(array $constraints): void
    {
        $this->constraints = $constraints;
    }

    /**
     * @param array<string, mixed> $options
     */
    public function assignValues(array $options): ScriptRule
    {
        $this->values = $options;

        return $this;
    }

    /**
     * @return array<string, mixed>
     */
    public function getValues(): array
    {
        return $this->values;
    }

    /**
     * @param array<string, mixed> $context
     *
     * @throws SyntaxError
     * @throws RuntimeError
     * @throws LoaderError
     */
    private function render(TwigEnvironment $twig, Script $script, Hook $hook, string $name, array $context): bool
    {
        if (!$this->traces) {
            return filter_var(trim($twig->render($name, $context)), \FILTER_VALIDATE_BOOLEAN);
        }

        $match = false;
        $this->traces->trace($hook, $script, static function (Debug $debug) use ($twig, $name, $context, &$match): void {
            $twig->addGlobal('debug', $debug);

            $rendered = $twig->render($name, $context);
            $match = filter_var(trim($rendered), \FILTER_VALIDATE_BOOLEAN);

            $debug->dump($match, 'return');
        });

        return $match;
    }
}
