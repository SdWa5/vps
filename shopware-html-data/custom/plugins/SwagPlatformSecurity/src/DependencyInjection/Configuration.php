<?php declare(strict_types=1);

namespace Swag\Security\DependencyInjection;

use Shopware\Core\Framework\DependencyInjection\Configuration as CoreConfiguration;
use Symfony\Component\Config\Definition\Builder\ArrayNodeDefinition;
use Symfony\Component\Config\Definition\Builder\TreeBuilder;

class Configuration extends CoreConfiguration
{
    public function getConfigTreeBuilder(): TreeBuilder
    {
        $treeBuilder = parent::getConfigTreeBuilder();

        if (self::hasSearchSection()) {
            return $treeBuilder;
        }

        $rootNode = $treeBuilder->getRootNode();
        if (!$rootNode instanceof ArrayNodeDefinition) {
            return $treeBuilder;
        }

        $rootNode
            ->children()
                ->append($this->createSearchSection())
            ->end();

        return $treeBuilder;
    }

    public static function hasSearchSection(): bool
    {
        $rootNode = (new CoreConfiguration())->getConfigTreeBuilder()->getRootNode();
        if (!$rootNode instanceof ArrayNodeDefinition) {
            return false;
        }

        return ($rootNode->getChildNodeDefinitions()['search'] ?? []) !== [];
    }

    private function createSearchSection(): ArrayNodeDefinition
    {
        $treeBuilder = new TreeBuilder('search');

        $rootNode = $treeBuilder->getRootNode();
        $rootNode
            ->children()
                ->integerNode('term_max_length')->defaultValue(300)->end()
            ->end();

        return $rootNode;
    }
}
