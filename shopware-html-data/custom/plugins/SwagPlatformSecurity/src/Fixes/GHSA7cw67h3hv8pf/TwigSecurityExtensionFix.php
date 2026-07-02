<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA7cw67h3hv8pf;

use Shopware\Core\Content\Seo\SeoUrlTwigFactory;
use Shopware\Core\Framework\Adapter\Twig\SecurityExtension;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Rule\ScriptRule;
use Shopware\Core\Framework\Script\Execution\ScriptExecutor;
use Swag\Security\Components\AbstractSecurityFix;
use Symfony\Component\DependencyInjection\ContainerBuilder;
use Symfony\Component\DependencyInjection\ContainerInterface;

#[Package('framework')]
class TwigSecurityExtensionFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-7cw6-7h3h-v8pf';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.6.1';
    }

    public static function boot(ContainerInterface $container): void
    {
        // Outside CI execution, the class shouldn't be loaded yet, therefore we can override it with manual require
        if (class_exists(ScriptRule::class, false) === false) {
            // The class is created inline, so we need to overwrite the definition with a manual require here
            require_once __DIR__ . '/ScriptRule.php';
        }
    }

    public static function buildContainer(ContainerBuilder $container): void
    {
        $definition = $container->getDefinition(SecurityExtension::class);
        $definition->setClass(PatchedSecurityExtension::class);

        $scriptExecutorDefinition = $container->getDefinition(ScriptExecutor::class);
        $scriptExecutorDefinition->setClass(PatchedScriptExecutor::class);

        $seoUrlTwigFactoryDefinition = $container->getDefinition(SeoUrlTwigFactory::class);
        $seoUrlTwigFactoryDefinition->setClass(PatchedSeoUrlTwigFactory::class);
    }
}
